# ============================================================
# database/variables.tf
# ============================================================

variable "project_name" {
  description = "Prefijo para el nombre de todos los recursos"
  type        = string
  default     = "aws-3tier"
}

variable "db_subnet_ids" {
  description = "IDs de las subredes privadas DB (para el DB Subnet Group)"
  type        = list(string)
}

variable "sg_database_id" {
  description = "ID del Security Group sg_database (acepta MySQL desde sg_backend)"
  type        = string
}

variable "db_instance_class" {
  description = "Tipo de instancia RDS (Free Tier: db.t3.micro)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Versión del motor MySQL"
  type        = string
  default     = "8.0"
}

variable "db_allocated_storage" {
  description = "Almacenamiento inicial en GB"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Nombre de la base de datos inicial"
  type        = string
  default     = "appcitas"
}

variable "db_username" {
  description = "Usuario administrador de la base de datos"
  type        = string
  default     = "admin"
}

variable "db_password" {
  description = "Contraseña del usuario admin — viene de terraform.tfvars (en .gitignore)"
  type        = string
  sensitive   = true
}

variable "multi_az" {
  description = "Habilitar Multi-AZ en RDS"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Omitir snapshot al destruir (true para dev/prod con backups externos)"
  type        = bool
  default     = true
}


variable "tags" {
  description = "Tags comunes aplicados a todos los recursos"
  type        = map(string)
  default     = {}
}
