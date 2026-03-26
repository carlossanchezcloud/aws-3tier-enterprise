# ============================================================
# database/outputs.tf
# ============================================================

output "rds_endpoint" {
  description = "Endpoint de conexión RDS (host:port) — pasar al user_data del backend"
  value       = aws_db_instance.main.endpoint
}

output "rds_host" {
  description = "Hostname del endpoint RDS (sin puerto)"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "Puerto del endpoint RDS (MySQL: 3306)"
  value       = aws_db_instance.main.port
}

output "rds_db_name" {
  description = "Nombre de la base de datos inicial"
  value       = aws_db_instance.main.db_name
}

output "rds_identifier" {
  description = "Identificador de la instancia RDS"
  value       = aws_db_instance.main.identifier
}

output "rds_arn" {
  description = "ARN de la instancia RDS"
  value       = aws_db_instance.main.arn
}
