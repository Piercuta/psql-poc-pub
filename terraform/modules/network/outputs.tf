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

output "private_subnet_ids" {
  description = "IDs of the private subnets (egress through the NAT Gateway)."
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value       = aws_subnet.public[*].id
}

output "nat_public_ip" {
  description = "Public IP of the NAT Gateway (egress IP of the private subnets)."
  value       = aws_eip.nat.public_ip
}
