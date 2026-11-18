# Reads config.yaml and turns it into flat maps usable with for_each.
# This file only contains locals and the configuration checks (no PostgreSQL access).

locals {
  config = yamldecode(file("${path.module}/config.yaml")).configuration

  allowed_statuses = toset(["active", "retired"])

  # Privileges of each level, defined once here. "owner" is not a grant: the login
  # owns the schema.
  levels = {
    reader = {
      table_privileges    = ["SELECT"]
      sequence_privileges = ["SELECT"]
    }
    writer = {
      table_privileges    = ["SELECT", "INSERT", "UPDATE", "DELETE"]
      sequence_privileges = ["SELECT", "UPDATE"] # UPDATE allows nextval()
    }
  }

  # Schemas accept either a plain string ("catalog") or {name, status}.
  databases = {
    for db, cfg in local.config.databases : db => {
      status = try(cfg.status, "active")
      schemas = [
        for s in cfg.schemas : {
          name   = try(s.name, s)
          status = try(s.status, "active")
        }
      ]
      extensions = tolist(try(cfg.extensions, []))
    }
  }

  logins = {
    for l in local.config.logins : l.username => {
      authentication = try(l.authentication, "password")
    }
  }

  mappings = [
    for m in local.config.mappings : {
      level    = m.level
      username = m.username
      database = m.database
      schema   = try(m.schema, null)
    }
  ]

  # All schemas stay in state while listed (active or retired).
  schemas = {
    for item in flatten([
      for db, cfg in local.databases : [
        for s in cfg.schemas : {
          key      = "${db}/${s.name}"
          database = db
          schema   = s.name
          status   = s.status
        }
      ]
    ]) : item.key => item
  }

  active_schema_names = {
    for db, cfg in local.databases : db => [
      for s in cfg.schemas : s.name if s.status == "active"
    ]
  }

  extensions = {
    for item in flatten([
      for db, cfg in local.databases : [
        for e in cfg.extensions : { key = "${db}/${e}", database = db, extension = e }
      ]
    ]) : item.key => item
  }

  # --- Schema ownership -------------------------------------------------------
  owners_by_schema = {
    for m in local.mappings : "${m.database}/${m.schema}" => m.username...
    if m.level == "owner" && m.schema != null
  }

  owners_by_database = {
    for m in local.mappings : m.database => m.username...
    if m.level == "owner" && m.schema == null
  }

  # Effective owner of each schema: the schema mapping wins over the database mapping.
  schema_owner = {
    for k, s in local.schemas : k => try(
      local.owners_by_schema[k][0],
      try(local.owners_by_database[s.database][0], null)
    )
  }

  owner_logins = toset(compact([for k, o in local.schema_owner : o]))

  # Grants only on *active* schemas. Database-wide mappings expand to active schemas only.
  expanded_mappings = flatten([
    for m in local.mappings : [
      for s in(
        m.schema != null
        ? tolist([m.schema])
        : try(local.active_schema_names[m.database], [])
        ) : {
        username = m.username
        database = m.database
        schema   = s
        level    = m.level
      }
    ]
  ])

  access_grouped = {
    for e in local.expanded_mappings : "${e.username}/${e.database}/${e.schema}" => e...
  }

  access = {
    for k, items in local.access_grouped : k => {
      username = items[0].username
      database = items[0].database
      schema   = items[0].schema
      level = (
        contains(items[*].level, "owner") ? "owner" :
        contains(items[*].level, "writer") ? "writer" : "reader"
      )
    }
  }

  access_grants = {
    for k, a in local.access : k => a
    if a.level != "owner" && try(local.schemas["${a.database}/${a.schema}"].status, "active") == "active"
  }

  connect_grants = {
    for pair in distinct([for a in values(local.access) : "${a.username}/${a.database}"]) : pair => {
      username = split("/", pair)[0]
      database = split("/", pair)[1]
    }
  }
}

resource "terraform_data" "validate_config" {
  lifecycle {
    precondition {
      condition     = alltrue([for l in local.logins : l.authentication == "password"])
      error_message = "Only authentication \"password\" is supported for logins."
    }

    precondition {
      condition     = alltrue([for db, cfg in local.databases : contains(local.allowed_statuses, cfg.status)])
      error_message = "Database status must be active or retired."
    }

    precondition {
      condition     = alltrue([for k, s in local.schemas : contains(local.allowed_statuses, s.status)])
      error_message = "Schema status must be active or retired."
    }

    precondition {
      condition     = alltrue([for m in local.mappings : contains(["owner", "reader", "writer"], m.level)])
      error_message = "Mapping level must be one of: owner, reader, writer."
    }

    precondition {
      condition     = alltrue([for m in local.mappings : contains(keys(local.logins), m.username)])
      error_message = "A mapping references a username that is not declared in logins."
    }

    precondition {
      condition     = alltrue([for m in local.mappings : contains(keys(local.databases), m.database)])
      error_message = "A mapping references a database that is not declared in databases."
    }

    precondition {
      condition = alltrue([
        for m in local.mappings :
        m.schema == null ? true : contains(keys(local.schemas), "${m.database}/${m.schema}")
      ])
      error_message = "A mapping references a schema that is not declared for its database."
    }

    precondition {
      condition = alltrue([
        for m in local.mappings :
        m.schema == null ? true : local.schemas["${m.database}/${m.schema}"].status == "active"
      ])
      error_message = "A mapping references a retired schema. Remove the mapping, then run the destroy-schema workflow."
    }

    precondition {
      condition     = alltrue([for k, owners in local.owners_by_schema : length(owners) == 1])
      error_message = "A schema has several owner mappings: a schema can only have one owner."
    }

    precondition {
      condition     = alltrue([for k, owners in local.owners_by_database : length(owners) == 1])
      error_message = "A database has several database-wide owner mappings: use one owner, or map schemas individually."
    }
  }
}
