resource "vault_mount" "database" {
  namespace = vault_namespace.env.path_fq
  path      = "database"
  type      = "database"
}

resource "vault_database_secret_backend_connection" "postgres" {
  namespace     = vault_namespace.env.path_fq
  backend       = vault_mount.database.path
  name          = "netlix-db"
  allowed_roles = ["netlix-readwrite"]

  postgresql {
    connection_url = "postgresql://{{username}}:{{password}}@${var.rds_endpoint}/${var.db_name}?sslmode=require"
    username       = var.rds_admin_username
    password       = var.rds_admin_password
  }
}

resource "vault_database_secret_backend_role" "app" {
  namespace   = vault_namespace.env.path_fq
  backend     = vault_mount.database.path
  name        = "netlix-readwrite"
  db_name     = vault_database_secret_backend_connection.postgres.name
  default_ttl = 3600
  max_ttl     = 86400

  creation_statements = [
    "CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}';",
    "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";",
    "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO \"{{name}}\";",
  ]

  revocation_statements = [
    "ALTER ROLE \"{{name}}\" NOLOGIN;",
    "REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\";",
  ]
}
