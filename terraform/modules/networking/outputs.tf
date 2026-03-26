# ============================================================
# networking/outputs.tf
# ============================================================

# ── VPC ──────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  value       = aws_vpc.main.cidr_block
}

# ── Subredes ─────────────────────────────────────────────────
output "public_subnet_ids" {
  description = "IDs de las subredes públicas (ALB)"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs de las subredes privadas de app (Website + Backend)"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "IDs de las subredes privadas de base de datos (RDS)"
  value       = aws_subnet.private_db[*].id
}

# ── NAT Instance ─────────────────────────────────────────────
output "nat_instance_id" {
  description = "ID de la NAT Instance"
  value       = aws_instance.nat.id
}

output "nat_public_ip" {
  description = "IP pública estática de la NAT Instance (EIP)"
  value       = aws_eip.nat.public_ip
}

output "nat_network_interface_id" {
  description = "ENI primaria de la NAT Instance (referenciada en rutas privadas)"
  value       = aws_instance.nat.primary_network_interface_id
}

# ── Security Groups ──────────────────────────────────────────
output "sg_alb_id" {
  description = "ID del Security Group del ALB"
  value       = aws_security_group.alb.id
}

output "sg_website_id" {
  description = "ID del Security Group de las instancias Website"
  value       = aws_security_group.website.id
}

output "sg_backend_id" {
  description = "ID del Security Group de las instancias Backend"
  value       = aws_security_group.backend.id
}

output "sg_database_id" {
  description = "ID del Security Group de RDS"
  value       = aws_security_group.database.id
}
