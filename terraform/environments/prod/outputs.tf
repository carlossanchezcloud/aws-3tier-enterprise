# ============================================================
# environments/prod/outputs.tf
# ============================================================

# ── Acceso público ────────────────────────────────────────────
output "alb_dns_name" {
  description = "DNS del ALB — apuntar CNAME de dominio aquí"
  value       = module.compute.alb_dns_name
}

output "cloudfront_domain_name" {
  description = "URL de CloudFront para el frontend estático"
  value       = module.storage.cloudfront_domain_name
}

output "frontend_bucket_name" {
  description = "Nombre del bucket S3 del frontend — configurar como GitHub Variable S3_FRONTEND_BUCKET"
  value       = module.storage.frontend_bucket_name
}

output "cloudfront_distribution_id" {
  description = "ID de la distribución CloudFront — configurar como GitHub Variable CLOUDFRONT_DISTRIBUTION_ID"
  value       = module.storage.cloudfront_distribution_id
}

# ── Base de datos ─────────────────────────────────────────────
output "rds_endpoint" {
  description = "Endpoint RDS (no expuesto a Internet — solo para referencia)"
  value       = module.database.rds_endpoint
  sensitive   = true
}

output "rds_db_name" {
  description = "Nombre de la base de datos inicial"
  value       = module.database.rds_db_name
}

# ── Networking ────────────────────────────────────────────────
output "vpc_id" {
  description = "ID de la VPC"
  value       = module.networking.vpc_id
}

output "nat_instance_id" {
  description = "ID de la NAT Instance (para validaciones y troubleshooting)"
  value       = module.networking.nat_instance_id
}

output "nat_public_ip" {
  description = "IP pública estática de la NAT Instance"
  value       = module.networking.nat_public_ip
}

# ── Compute ───────────────────────────────────────────────────
output "asg_name" {
  description = "Nombre del Auto Scaling Group del Backend"
  value       = module.compute.asg_name
}

# ── Security Groups (para validate.ps1) ──────────────────────
output "sg_alb_id" {
  description = "ID del SG del ALB"
  value       = module.networking.sg_alb_id
}

output "sg_backend_id" {
  description = "ID del SG del Backend"
  value       = module.networking.sg_backend_id
}

output "sg_database_id" {
  description = "ID del SG de RDS"
  value       = module.networking.sg_database_id
}

# ── RDS identifier (para validate.ps1) ───────────────────────
output "rds_identifier" {
  description = "Identificador de la instancia RDS"
  value       = module.database.rds_identifier
}

# ── IAM ───────────────────────────────────────────────────────
output "github_actions_role_arn" {
  description = "ARN del IAM Role para GitHub Actions — usar como role-to-assume en workflows"
  value       = aws_iam_role.github_actions.arn
}
