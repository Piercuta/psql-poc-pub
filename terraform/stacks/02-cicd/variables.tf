variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI SSO profile used for deployment."
  type        = string
  default     = "piercuta-dev"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose workflows run on the CodeBuild runner."
  type        = string
  default     = "Piercuta/psql-poc-pub"
}

variable "codeconnections_arn" {
  description = "ARN of the AWS CodeConnections connection to GitHub (must be in AVAILABLE state)."
  type        = string
  default     = "arn:aws:codeconnections:eu-west-1:532673134317:connection/2a30a395-8d38-43ab-827b-f39a83c9986a"
}

variable "state_bucket" {
  description = "S3 bucket holding the Terraform states."
  type        = string
  default     = "piercuta-terraform-state"
}

variable "state_key_prefix" {
  description = "Key prefix of the Terraform states of this project inside the state bucket."
  type        = string
  default     = "psql-poc"
}

variable "runner_compute_type" {
  description = "CodeBuild compute type of the runner."
  type        = string
  default     = "BUILD_GENERAL1_SMALL"
}

variable "log_retention_days" {
  description = "Retention in days of the runner CloudWatch logs."
  type        = number
  default     = 14
}
