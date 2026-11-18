data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "psql-poc-${var.environment}"
  azs  = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

module "network" {
  source = "../../modules/network"

  name               = local.name
  vpc_cidr           = var.vpc_cidr
  availability_zones = local.azs
}

module "aurora" {
  source = "../../modules/aurora-postgres"

  name                = local.name
  vpc_id              = module.network.vpc_id
  subnet_ids          = module.network.isolated_subnet_ids
  allowed_cidr_blocks = [module.network.vpc_cidr]

  engine_version = var.engine_version
  min_capacity   = var.min_capacity
  max_capacity   = var.max_capacity

  # Dev settings: easy teardown.
  deletion_protection = false
  skip_final_snapshot = true
}
