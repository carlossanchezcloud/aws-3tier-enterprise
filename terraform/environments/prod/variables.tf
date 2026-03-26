# ============================================================
# environments/prod/variables.tf
# ============================================================

variable "aws_region" {
  description = "Región AWS donde se despliega la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo para el nombre de todos los recursos"
  type        = string
  default     = "aws-3tier"
}

# ── Networking ────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR de la VPC principal"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Availability Zones a utilizar (mínimo 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subredes públicas (ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDRs para subredes privadas app (Website + Backend EC2)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDRs para subredes privadas DB (RDS)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

# ── Database (sensible — viene de terraform.tfvars en .gitignore) ──
variable "db_password" {
  description = "Contraseña del usuario admin de RDS MySQL — NUNCA hardcodear aquí"
  type        = string
  sensitive   = true
}
