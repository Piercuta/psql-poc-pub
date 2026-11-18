variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "aws_profile" {
  description = "AWS CLI profile. Leave null in CodeBuild (the runner IAM role is used)."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
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