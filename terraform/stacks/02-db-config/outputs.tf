output "databases" {
  description = "Created databases with their schemas, schema owners and extensions."
  value = {
    for db, cfg in local.databases : db => {
      schemas = {
        # The master username is sensitive (read from Secrets Manager): do not expose it.
        for s in cfg.schemas : s => coalesce(local.schema_owner["${db}/${s}"], "(master user)")
      }
      extensions = cfg.extensions
    }
  }
}

output "login_secrets" {
  description = "Secrets Manager secret ARN holding the credentials of each login."
  value       = { for k, s in aws_secretsmanager_secret.login : k => s.arn }
}
