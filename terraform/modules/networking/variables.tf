# ============================================================
# networking/variables.tf
# ============================================================

variable "project_name" {
  description = "Prefijo para el nombre de todos los recursos"
  type        = string
  default     = "aws-3tier"
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "Lista de Availability Zones a usar (mínimo 2)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs para las subredes públicas (ALB)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDRs para las subredes privadas de app (Website + Backend EC2)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDRs para las subredes privadas de base de datos (RDS)"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "nat_instance_type" {
  description = "Tipo de instancia EC2 para la NAT Instance (Free Tier: t3.micro)"
  type        = string
  default     = "t3.micro"
}

variable "tags" {
  description = "Tags comunes aplicados a todos los recursos"
  type        = map(string)
  default     = {}
}
