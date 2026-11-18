# Outputs of 01-infra (Aurora endpoint and master secret).
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.state_key_prefix}/${var.environment}/terraform.tfstate"
    region = var.region
  }
}

# Master credentials managed by RDS in Secrets Manager.
data "aws_secretsmanager_secret_version" "master" {
  secret_id = data.terraform_remote_state.infra.outputs.master_user_secret_arn
}

locals {
  db_host = data.terraform_remote_state.infra.outputs.cluster_endpoint
  db_port = data.terraform_remote_state.infra.outputs.cluster_port
  master  = jsondecode(data.aws_secretsmanager_secret_version.master.secret_string)
}

# One application role per database, with a generated password.
resource "random_password" "app" {
  for_each = var.databases

  length  = 32
  special = false
}

resource "postgresql_role" "app" {
  for_each = var.databases

  name        = "${each.key}_app"
  login       = true
  password    = random_password.app[each.key].result
  search_path = [each.value.schema]
}

# On RDS/Aurora the master user is not a superuser: it must be a member of a
# role before it can create objects owned by that role.
resource "postgresql_grant_role" "master_membership" {
  for_each = var.databases

  role       = local.master.username
  grant_role = postgresql_role.app[each.key].name
}

resource "postgresql_database" "this" {
  for_each = var.databases

  name  = each.key
  owner = postgresql_role.app[each.key].name

  depends_on = [postgresql_grant_role.master_membership]
}

resource "postgresql_schema" "this" {
  for_each = var.databases

  name          = each.value.schema
  database      = postgresql_database.this[each.key].name
  owner         = postgresql_role.app[each.key].name
  if_not_exists = true

  depends_on = [postgresql_grant_role.master_membership]
}

# Connection details for the applications, stored in Secrets Manager.
resource "aws_secretsmanager_secret" "app" {
  for_each = var.databases

  name                    = "${var.state_key_prefix}/${var.environment}/db/${each.key}"
  description             = "Application credentials for database ${each.key}"
  recovery_window_in_days = 0 # dev: allow immediate deletion and re-creation
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each = var.databases

  secret_id = aws_secretsmanager_secret.app[each.key].id
  secret_string = jsonencode({
    host     = local.db_host
    port     = local.db_port
    dbname   = postgresql_database.this[each.key].name
    schema   = postgresql_schema.this[each.key].name
    username = postgresql_role.app[each.key].name
    password = random_password.app[each.key].result
  })
}
