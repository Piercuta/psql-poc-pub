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

# ---------------------------------------------------------------------------
# Logins: one PostgreSQL role per login, with a generated password stored in
# Secrets Manager.
# ---------------------------------------------------------------------------
resource "random_password" "login" {
  for_each = local.logins

  length  = 32
  special = false

  depends_on = [terraform_data.validate_config]
}

resource "postgresql_role" "login" {
  for_each = local.logins

  name     = each.key
  login    = true
  password = random_password.login[each.key].result
}

resource "aws_secretsmanager_secret" "login" {
  for_each = local.logins

  name                    = "${var.state_key_prefix}/${var.environment}/db/login/${each.key}"
  description             = "PostgreSQL credentials of login ${each.key}"
  recovery_window_in_days = 0 # dev: allow immediate deletion and re-creation
}

resource "aws_secretsmanager_secret_version" "login" {
  for_each = local.logins

  secret_id = aws_secretsmanager_secret.login[each.key].id
  secret_string = jsonencode({
    host     = local.db_host
    port     = local.db_port
    username = postgresql_role.login[each.key].name
    password = random_password.login[each.key].result
  })
}

# On RDS/Aurora the master user is not a superuser: it must be a member of a
# role before it can create objects owned by that role.
resource "postgresql_grant_role" "master_membership" {
  for_each = local.owner_logins

  role       = local.master.username
  grant_role = postgresql_role.login[each.key].name
}

# ---------------------------------------------------------------------------
# Databases, schemas and extensions
# ---------------------------------------------------------------------------
resource "postgresql_database" "db" {
  for_each = local.databases

  name = each.key

  # Always on: the normal pipeline cannot drop databases.
  # Real destroys go through the destroy-schema workflow (archive → SQL → state rm).
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [terraform_data.validate_config]
}

resource "postgresql_schema" "schema" {
  for_each = local.schemas

  name          = each.value.schema
  database      = postgresql_database.db[each.value.database].name
  owner         = local.schema_owner[each.key] != null ? postgresql_role.login[local.schema_owner[each.key]].name : null
  if_not_exists = true

  # Always on: the normal pipeline cannot drop schemas.
  # Real destroys go through the destroy-schema workflow (archive → SQL → state rm).
  lifecycle {
    prevent_destroy = true
  }

  depends_on = [postgresql_grant_role.master_membership]
}

resource "postgresql_extension" "extension" {
  for_each = local.extensions

  name     = each.value.extension
  database = postgresql_database.db[each.value.database].name
}

# ---------------------------------------------------------------------------
# Grants (readers and writers). Owners need no grant: they own their schemas.
# ---------------------------------------------------------------------------
resource "postgresql_grant" "database_connect" {
  for_each = local.connect_grants

  database    = postgresql_database.db[each.value.database].name
  role        = postgresql_role.login[each.value.username].name
  object_type = "database"
  privileges  = ["CONNECT"]
}

resource "postgresql_grant" "schema_usage" {
  for_each = local.access_grants

  database    = postgresql_database.db[each.value.database].name
  role        = postgresql_role.login[each.value.username].name
  schema      = postgresql_schema.schema["${each.value.database}/${each.value.schema}"].name
  object_type = "schema"
  privileges  = ["USAGE"]
}

# Existing tables and sequences.
resource "postgresql_grant" "tables" {
  for_each = local.access_grants

  database    = postgresql_database.db[each.value.database].name
  role        = postgresql_role.login[each.value.username].name
  schema      = postgresql_schema.schema["${each.value.database}/${each.value.schema}"].name
  object_type = "table"
  privileges  = local.levels[each.value.level].table_privileges
}

resource "postgresql_grant" "sequences" {
  for_each = local.access_grants

  database    = postgresql_database.db[each.value.database].name
  role        = postgresql_role.login[each.value.username].name
  schema      = postgresql_schema.schema["${each.value.database}/${each.value.schema}"].name
  object_type = "sequence"
  privileges  = local.levels[each.value.level].sequence_privileges
}

# Future tables and sequences created by the schema owner (the master user when the
# schema has no owner mapping).
resource "postgresql_default_privileges" "tables" {
  for_each = local.access_grants

  database    = postgresql_database.db[each.value.database].name
  role        = postgresql_role.login[each.value.username].name
  schema      = postgresql_schema.schema["${each.value.database}/${each.value.schema}"].name
  owner       = coalesce(local.schema_owner["${each.value.database}/${each.value.schema}"], local.master.username)
  object_type = "table"
  privileges  = local.levels[each.value.level].table_privileges

  depends_on = [postgresql_grant_role.master_membership]
}

resource "postgresql_default_privileges" "sequences" {
  for_each = local.access_grants

  database    = postgresql_database.db[each.value.database].name
  role        = postgresql_role.login[each.value.username].name
  schema      = postgresql_schema.schema["${each.value.database}/${each.value.schema}"].name
  owner       = coalesce(local.schema_owner["${each.value.database}/${each.value.schema}"], local.master.username)
  object_type = "sequence"
  privileges  = local.levels[each.value.level].sequence_privileges

  depends_on = [postgresql_grant_role.master_membership]
}
