variable "tenants" {
  description = "List of tenants"
  type = list(object({
    id = string
  }))
  default = []
}

variable "db_password" {
  description = "Password for the database"
  type = string
  sensitive = true
}

resource "aws_db_subnet_group" "main" {
  name       = "rds-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "rds-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = "multitenant-db"

  engine         = "postgres"
  engine_version = "15.3"
  instance_class = "db.t3.micro"

  allocated_storage     = 100
  storage_encrypted     = true
  storage_type          = "gp3"

  db_name  = "multitenant"
  username = "admin"
  password = var.db_password  # usar Secrets Manager en prod

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  backup_retention_period = 7
  backup_window          = "03:00-04:00"
  maintenance_window     = "mon:04:00-mon:05:00"

  deletion_protection = true
  skip_final_snapshot = false
  final_snapshot_identifier = "multitenant-db-final"

  tags = {
    Name = "multitenant-postgres"
  }
}

# Esquema RLS (Row Level Security) en PostgreSQL
resource "postgresql_schema" "tenant_schema" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  name = each.value.id
  owner = "admin"
}

resource "postgresql_role" "tenant_role" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  name     = "role_${each.value.id}"
  login    = true
  password = random_password.tenant_db_passwords[each.key].result
}

resource "random_password" "tenant_db_passwords" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  length  = 24
  special = false
}

# Ejemplo de tabla con RLS
# (esto se ejecutaría con provider postgresql o después con un job)
resource "postgresql_table" "tenant_data" {
  for_each = {
    for t in var.tenants : 
    t.id => t
  }

  schema = postgresql_schema.tenant_schema[each.key].name
  name   = "tenant_data"

  column {
    name = "id"
    type = "SERIAL"
    not_null = true
  }

  column {
    name = "tenant_id"
    type = "TEXT"
    not_null = true
  }

  column {
    name = "data"
    type = "JSONB"
  }

  column {
    name = "created_at"
    type = "TIMESTAMP"
    default = "CURRENT_TIMESTAMP"
  }
}
