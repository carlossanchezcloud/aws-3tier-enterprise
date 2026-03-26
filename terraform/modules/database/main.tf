# ============================================================
# database/main.tf
#
# Recursos:
#   - DB Subnet Group (subredes privadas DB)
#   - DB Parameter Group (MySQL 8.0, charset utf8mb4)
#   - RDS MySQL 8.0 — Multi-AZ, cifrado, sin acceso público
# ============================================================

locals {
  name = var.project_name
}

# ── DB Subnet Group ───────────────────────────────────────────
# RDS necesita un subnet group con subredes en al menos 2 AZs
# aunque Multi-AZ se configure aparte.
resource "aws_db_subnet_group" "main" {
  name        = "${local.name}-db-subnet-group"
  description = "Subnet group para RDS MySQL — subredes privadas DB (AZ1 + AZ2)"
  subnet_ids  = var.db_subnet_ids

  tags = merge(var.tags, {
    Name = "${local.name}-db-subnet-group"
  })
}

# ── DB Parameter Group ────────────────────────────────────────
# utf8mb4 es el charset correcto para MySQL 8.0 (soporta emojis y
# todos los caracteres Unicode, incluyendo los necesarios para
# nombres en español con tildes y ñ).
resource "aws_db_parameter_group" "mysql8" {
  name        = "${local.name}-mysql8-params"
  family      = "mysql8.0"
  description = "Parametros MySQL 8.0: charset utf8mb4, collation utf8mb4_unicode_ci"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  # Habilitar slow query log para diagnóstico de rendimiento
  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  tags = merge(var.tags, {
    Name = "${local.name}-mysql8-params"
  })
}

# ── RDS MySQL 8.0 ─────────────────────────────────────────────
#
# Decisiones de diseño:
#   - multi_az = true: AWS mantiene una réplica síncrona en AZ2.
#     Si AZ1 falla, el failover automático ocurre en ~60-120s.
#     El endpoint DNS NO cambia — la aplicación reconecta al mismo host.
#   - publicly_accessible = false: el endpoint RDS nunca tiene
#     ruta desde Internet. Solo accesible desde sg_backend.
#   - storage_encrypted = true: AES-256 con KMS (clave administrada por AWS).
#     Sin costo adicional para gp2 < 100GB.
#   - performance_insights_enabled = false: requiere db.t3.medium+
#     para la tier gratuita extendida. Omitido para Free Tier.
#
resource "aws_db_instance" "main" {
  identifier = "${local.name}-rds"

  # Motor
  engine         = "mysql"
  engine_version = var.db_engine_version

  # Hardware
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp2"
  storage_encrypted = true

  # Base de datos inicial
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Red y seguridad
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.sg_database_id]
  publicly_accessible    = false # NUNCA exponer RDS a Internet

  # Parámetros
  parameter_group_name = aws_db_parameter_group.mysql8.name

  # Alta disponibilidad
  multi_az = var.multi_az

  # Backups
  backup_retention_period = var.backup_retention_days
  backup_window           = "03:00-04:00"      # UTC — 00:00-01:00 EST
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Performance Insights no disponible en Free Tier para db.t3.micro
  performance_insights_enabled = false

  # Ciclo de vida
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = false # Cambiar a true antes de producción real

  # Actualizaciones automáticas de parches menores (seguridad)
  auto_minor_version_upgrade = true

  tags = merge(var.tags, {
    Name = "${local.name}-rds"
  })
}
