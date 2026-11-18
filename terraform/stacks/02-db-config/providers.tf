terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# In CodeBuild the credentials come from the runner IAM role (aws_profile = null).
provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "psql-poc"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# The Aurora cluster lives in isolated subnets: this provider only works from
# inside the VPC (the CodeBuild runner), both for plan and apply.
provider "postgresql" {
  host      = local.db_host
  port      = local.db_port
  database  = "postgres"
  username  = local.master.username
  password  = local.master.password
  sslmode   = "require"
  superuser = false # RDS/Aurora master user is not a real superuser

  connect_timeout = 15
}
