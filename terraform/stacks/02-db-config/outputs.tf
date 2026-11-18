output "databases" {
  description = "Created databases with their schemas, schema owners and extensions."
  value = {
    for db, cfg in local.databases : db => {
      schemas = {
        for s in cfg.schemas : s => coalesce(local.schema_owner["${db}/${s}"], local.master.username)
      }
      extensions = cfg.extensions
    }
  }
}

output "login_secrets" {
  description = "Secrets Manager secret ARN holding the credentials of each login."
  value       = { for k, s in aws_secretsmanager_secret.login : k => s.arn }
}
