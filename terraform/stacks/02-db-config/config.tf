# Reads config.yaml and turns it into flat maps usable with for_each.
# This file only contains locals and the configuration checks (no PostgreSQL access).

locals {
  config = yamldecode(file("${path.module}/config.yaml")).configuration

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

  databases = {
    for db, cfg in local.config.databases : db => {
      schemas    = tolist(cfg.schemas)
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

  schemas = {
    for item in flatten([
      for db, cfg in local.databases : [
        for s in cfg.schemas : { key = "${db}/${s}", database = db, schema = s }
      ]
    ]) : item.key => item
  }

  extensions = {
    for item in flatten([
      for db, cfg in local.databases : [
        for e in cfg.extensions : { key = "${db}/${e}", database = db, extension = e }
      ]
    ]) : item.key => item
  }

  # --- Schema ownership -------------------------------------------------------
  # Owner mappings grouped by schema (specific) and by database (every schema).
  # Values are lists so that duplicates can be detected by the checks below.
  owners_by_schema = {
    for m in local.mappings : "${m.database}/${m.schema}" => m.username...
    if m.level == "owner" && m.schema != null
  }

  owners_by_database = {
    for m in local.mappings : m.database => m.username...
    if m.level == "owner" && m.schema == null
  }

  # Effective owner of each schema: the schema mapping wins over the database mapping.
  # null means the schema stays owned by the master user.
  schema_owner = {
    for k, s in local.schemas : k => try(
      local.owners_by_schema[k][0],
      try(local.owners_by_database[s.database][0], null)
    )
  }

  # Logins that own at least one schema.
  owner_logins = toset(compact([for k, o in local.schema_owner : o]))

  # --- Access (reader / writer / owner) per login, database and schema ---------
  expanded_mappings = flatten([
    for m in local.mappings : [
      for s in(m.schema != null ? tolist([m.schema]) : try(local.databases[m.database].schemas, [])) : {
        username = m.username
        database = m.database
        schema   = s
        level    = m.level
      }
    ]
  ])

  access_grouped = {
    for e in local.expanded_mappings : "${e.username}|${e.database}|${e.schema}" => e...
  }

  # When several mappings target the same login and schema, the highest level wins.
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

  # Reader and writer grants. A login that owns the schema needs no grant, and a
  # database-wide owner whose schema is owned by someone else gets no rights on it.
  access_grants = {
    for k, a in local.access : k => a if a.level != "owner"
  }

  # Every (login, database) pair that needs CONNECT.
  connect_grants = {
    for pair in distinct([for a in values(local.access) : "${a.username}|${a.database}"]) : pair => {
      username = split("|", pair)[0]
      database = split("|", pair)[1]
    }
  }
}

# Configuration checks. Other resources depend on it so that nothing is created when
# config.yaml is invalid.
resource "terraform_data" "validate_config" {
  lifecycle {
    precondition {
      condition     = alltrue([for l in local.logins : l.authentication == "password"])
      error_message = "Only authentication \"password\" is supported for logins."
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
        m.schema == null ? true : contains(try(local.databases[m.database].schemas, []), m.schema)
      ])
      error_message = "A mapping references a schema that is not declared for its database."
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
