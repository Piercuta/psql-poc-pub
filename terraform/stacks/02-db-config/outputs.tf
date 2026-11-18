output "databases" {
  description = "Created databases with their schemas, status, owners and extensions."
  value = {
    for db, cfg in local.databases : db => {
      status = cfg.status
      schemas = {
        for s in cfg.schemas : s.name => {
          status = s.status
          # The master username is sensitive: do not expose it.
          owner = coalesce(local.schema_owner["${db}/${s.name}"], "(master user)")
        }
      }
      extensions = cfg.extensions
    }
  }
}

output "login_secrets" {
  description = "Secrets Manager secret ARN holding the credentials of each login."
  value       = { for k, s in aws_secretsmanager_secret.login : k => s.arn }
}

output "retired_schemas" {
  description = "Schemas marked retired (still in the cluster; destroy via destroy-schema workflow)."
  value = [
    for k, s in local.schemas : k if s.status == "retired"
  ]
}
