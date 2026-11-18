# Stack outputs of 01-infra (VPC, subnets, Aurora secret...).
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.environment}/terraform.tfstate"
    region = var.region
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name   = "psql-poc-${var.environment}-runner"
  infra  = data.terraform_remote_state.infra.outputs
  region = var.region
  acct   = data.aws_caller_identity.current.account_id
  part   = data.aws_partition.current.partition

  private_subnet_arns = [
    for id in local.infra.private_subnet_ids :
    "arn:${local.part}:ec2:${local.region}:${local.acct}:subnet/${id}"
  ]
}

# ---------------------------------------------------------------------------
# GitHub credential: CodeBuild uses the CodeConnections connection to talk to
# GitHub. Note: there is a single credential per server type (GITHUB) per
# account and region.
# ---------------------------------------------------------------------------
resource "aws_codebuild_source_credential" "github" {
  auth_type   = "CODECONNECTIONS"
  server_type = "GITHUB"
  token       = var.codeconnections_arn
}

# ---------------------------------------------------------------------------
# Networking: runner has no inbound traffic, outbound is open (GitHub, Terraform
# registry, AWS APIs through the NAT Gateway, Aurora inside the VPC).
# ---------------------------------------------------------------------------
resource "aws_security_group" "runner" {
  name        = local.name
  description = "CodeBuild GitHub Actions runner (no inbound)"
  vpc_id      = local.infra.vpc_id

  tags = {
    Name = local.name
  }
}

resource "aws_vpc_security_group_egress_rule" "runner_all" {
  security_group_id = aws_security_group.runner.id
  description       = "Allow all outbound traffic"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# IAM role of the runner. It is the identity used by Terraform in the workflow.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.acct]
    }
  }
}

resource "aws_iam_role" "runner" {
  name               = local.name
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_cloudwatch_log_group" "runner" {
  name              = "/aws/codebuild/${local.name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "runner" {
  # Logs
  statement {
    sid     = "Logs"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      aws_cloudwatch_log_group.runner.arn,
      "${aws_cloudwatch_log_group.runner.arn}:*",
    ]
  }

  # Network interfaces required by VPC builds
  statement {
    sid = "VpcNetworkInterfaces"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "VpcNetworkInterfacePermission"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:${local.part}:ec2:${local.region}:${local.acct}:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:Subnet"
      values   = local.private_subnet_arns
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }
  }

  # GitHub access through CodeConnections
  statement {
    sid = "CodeConnections"
    actions = [
      "codeconnections:GetConnection",
      "codeconnections:GetConnectionToken",
      "codeconnections:UseConnection",
    ]
    resources = [var.codeconnections_arn]
  }

  # Terraform state of this project (S3 native locking writes a .tflock object)
  statement {
    sid       = "StateBucketList"
    actions   = ["s3:ListBucket"]
    resources = ["arn:${local.part}:s3:::${var.state_bucket}"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${var.state_key_prefix}/*"]
    }
  }

  statement {
    sid       = "StateObjects"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:${local.part}:s3:::${var.state_bucket}/${var.state_key_prefix}/*"]
  }

  # Aurora master credentials (read by the postgresql provider)
  statement {
    sid       = "ReadMasterSecret"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [local.infra.master_user_secret_arn]
  }

  # Application credentials created by the 03-db-config stack
  statement {
    sid = "ManageAppSecrets"
    actions = [
      "secretsmanager:CreateSecret",
      "secretsmanager:DeleteSecret",
      "secretsmanager:DescribeSecret",
      "secretsmanager:GetSecretValue",
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:PutSecretValue",
      "secretsmanager:UpdateSecret",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
    ]
    resources = [
      "arn:${local.part}:secretsmanager:${local.region}:${local.acct}:secret:${var.state_key_prefix}/${var.environment}/*"
    ]
  }
}

resource "aws_iam_role_policy" "runner" {
  name   = "runner"
  role   = aws_iam_role.runner.id
  policy = data.aws_iam_policy_document.runner.json
}

# ---------------------------------------------------------------------------
# CodeBuild project acting as a GitHub Actions self-hosted runner.
# Workflows target it with:
#   runs-on: codebuild-<project name>-${{ github.run_id }}-${{ github.run_attempt }}
# ---------------------------------------------------------------------------
resource "aws_codebuild_project" "runner" {
  name          = local.name
  description   = "GitHub Actions runner inside the VPC (Terraform + PostgreSQL provider)"
  service_role  = aws_iam_role.runner.arn
  build_timeout = 30

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = var.runner_compute_type
    image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/${var.github_repository}.git"
    git_clone_depth = 1
  }

  vpc_config {
    vpc_id             = local.infra.vpc_id
    subnets            = local.infra.private_subnet_ids
    security_group_ids = [aws_security_group.runner.id]
  }

  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.runner.name
    }
  }

  depends_on = [
    aws_codebuild_source_credential.github,
    aws_iam_role_policy.runner,
  ]
}

# Webhook that starts a runner whenever a GitHub Actions job is queued.
resource "aws_codebuild_webhook" "runner" {
  project_name = aws_codebuild_project.runner.name
  build_type   = "BUILD"

  filter_group {
    filter {
      type    = "EVENT"
      pattern = "WORKFLOW_JOB_QUEUED"
    }
  }
}
