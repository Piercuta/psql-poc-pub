output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "isolated_subnet_ids" {
  description = "IDs of the isolated subnets."
  value       = module.network.isolated_subnet_ids
}

output "cluster_endpoint" {
  description = "Aurora writer endpoint."
  value       = module.aurora.cluster_endpoint
}

output "database_name" {
  description = "Name of the initial database."
  value       = module.aurora.database_name
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master credentials."
  value       = module.aurora.master_user_secret_arn
}

output "private_subnet_ids" {
  description = "IDs of the private subnets (egress through the NAT Gateway)."
  value       = module.network.private_subnet_ids
}

output "cluster_port" {
  description = "Aurora PostgreSQL port."
  value       = module.aurora.port
}

output "aurora_security_group_id" {
  description = "ID of the Aurora security group."
  value       = module.aurora.security_group_id
}

output "nat_public_ip" {
  description = "Public egress IP of the private subnets."
  value       = module.network.nat_public_ip
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild runner project."
  value       = aws_codebuild_project.runner.name
}

output "runs_on_label" {
  description = "Label to use in GitHub Actions workflows (runs-on)."
  value       = "codebuild-${aws_codebuild_project.runner.name}-$${{ github.run_id }}-$${{ github.run_attempt }}"
}

output "runner_role_arn" {
  description = "ARN of the IAM role assumed by the runner."
  value       = aws_iam_role.runner.arn
}

output "runner_security_group_id" {
  description = "ID of the runner security group."
  value       = aws_security_group.runner.id
}

output "db_archives_bucket" {
  description = "S3 bucket for pg_dump archives taken before destroy."
  value       = aws_s3_bucket.db_archives.bucket
}

output "db_archives_bucket_arn" {
  description = "ARN of the S3 archives bucket."
  value       = aws_s3_bucket.db_archives.arn
}
