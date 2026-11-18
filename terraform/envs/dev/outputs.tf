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
