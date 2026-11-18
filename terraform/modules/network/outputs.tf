output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "isolated_subnet_ids" {
  description = "IDs of the isolated subnets."
  value       = aws_subnet.isolated[*].id
}
