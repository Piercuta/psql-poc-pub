variable "name" {
  description = "Name prefix and cluster identifier."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC hosting the cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs (at least two AZs) used by the DB subnet group."
  type        = list(string)
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to PostgreSQL (port 5432)."
  type        = list(string)
}

variable "engine_version" {
  description = "Aurora PostgreSQL engine version (e.g. 17.5)."
  type        = string
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "app"
}

variable "master_username" {
  description = "Master username of the cluster."
  type        = string
  default     = "postgres_admin"
}

variable "min_capacity" {
  description = "Minimum Serverless v2 capacity in ACUs (0 enables auto-pause)."
  type        = number
  default     = 0
}

variable "max_capacity" {
  description = "Maximum Serverless v2 capacity in ACUs."
  type        = number
  default     = 2
}

variable "kms_key_id" {
  description = "KMS key ARN for storage encryption. Null uses the AWS managed key aws/rds."
  type        = string
  default     = null
}

variable "backup_retention_period" {
  description = "Number of days to retain automated backups."
  type        = number
  default     = 1
}

variable "deletion_protection" {
  description = "Whether deletion protection is enabled on the cluster."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Whether to skip the final snapshot when the cluster is destroyed."
  type        = bool
  default     = true
}

variable "apply_immediately" {
  description = "Whether modifications are applied immediately instead of during the maintenance window."
  type        = bool
  default     = true
}
