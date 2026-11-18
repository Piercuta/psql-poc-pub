output "databases" {
  description = "Created databases with their schema and application role."
  value = {
    for k, v in var.databases : k => {
      database = postgresql_database.this[k].name
      schema   = postgresql_schema.this[k].name
      role     = postgresql_role.app[k].name
      secret   = aws_secretsmanager_secret.app[k].arn
    }
  }
}
