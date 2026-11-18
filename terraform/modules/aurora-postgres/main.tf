terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

locals {
  # Parameter group family follows the engine major version (e.g. "17.5" -> "aurora-postgresql17").
  parameter_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name}-subnet-group"
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-aurora-sg"
  description = "Aurora PostgreSQL access from inside the VPC"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-aurora-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-cluster-pg"
  family      = local.parameter_group_family
  description = "Cluster parameter group for ${var.name}"

  tags = {
    Name = "${var.name}-cluster-pg"
  }
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = var.name
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # Required for Serverless v2
  engine_version     = var.engine_version
  database_name      = var.database_name
  master_username    = var.master_username

  # The master password is generated and rotated by RDS and stored in Secrets Manager.
  manage_master_user_password = true

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name
  port                            = 5432
  network_type                    = "IPV4"

  storage_encrypted = true
  kms_key_id        = var.kms_key_id # null => AWS managed key (aws/rds)

  backup_retention_period = var.backup_retention_period
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-snapshot"
  apply_immediately         = var.apply_immediately

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = {
    Name = var.name
  }
}

# Single writer instance running on Serverless v2 capacity.
resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.name}-writer"
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = "db.serverless"

  publicly_accessible = false
  apply_immediately   = var.apply_immediately

  tags = {
    Name = "${var.name}-writer"
  }
}
