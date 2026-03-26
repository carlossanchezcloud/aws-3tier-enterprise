# ============================================================
# compute/variables.tf
# ============================================================

variable "project_name" {
  description = "Prefijo para el nombre de todos los recursos"
  type        = string
  default     = "aws-3tier"
}

variable "aws_region" {
  description = "Región AWS (necesaria para el user_data)"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "ID de la VPC donde se despliega el compute"
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs de subredes públicas para el ALB"
  type        = list(string)
}

variable "private_app_subnet_ids" {
  description = "IDs de subredes privadas app para las instancias EC2 del ASG"
  type        = list(string)
}

variable "sg_alb_id" {
  description = "ID del Security Group del ALB"
  type        = string
}

variable "sg_backend_id" {
  description = "ID del Security Group de las instancias Backend"
  type        = string
}

variable "rds_endpoint" {
  description = "Endpoint RDS (host:puerto) — inyectado en el .env del backend"
  type        = string
}

variable "db_password" {
  description = "Contraseña RDS — inyectada en el .env del backend via user_data"
  type        = string
  sensitive   = true
}

variable "instance_type" {
  description = "Tipo de instancia EC2 para el Backend (Free Tier: t3.micro)"
  type        = string
  default     = "t3.micro"
}

variable "ebs_volume_size_gb" {
  description = "Tamaño del volumen EBS raíz en GB"
  type        = number
  default     = 30
}

variable "asg_min_size" {
  description = "Número mínimo de instancias en el ASG"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Número máximo de instancias en el ASG"
  type        = number
  default     = 4
}

variable "asg_desired_capacity" {
  description = "Capacidad deseada del ASG (una instancia por AZ)"
  type        = number
  default     = 2
}

variable "health_check_path" {
  description = "Path del health check del Target Group"
  type        = string
  default     = "/health"
}

variable "app_port" {
  description = "Puerto en el que escucha la aplicación Node.js"
  type        = number
  default     = 3000
}

variable "tags" {
  description = "Tags comunes aplicados a todos los recursos"
  type        = map(string)
  default     = {}
}
