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

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (and isolated subnets) to use."
  type        = number
  default     = 2
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version."
  type        = string
  default     = "17.5"
}

variable "min_capacity" {
  description = "Minimum Serverless v2 capacity in ACUs."
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Maximum Serverless v2 capacity in ACUs."
  type        = number
  default     = 2
}
