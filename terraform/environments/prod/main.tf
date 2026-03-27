# ============================================================
# environments/prod/main.tf
#
# Punto de entrada principal. Llama a los módulos en orden:
#   1. networking  → VPC, subredes, NAT, SGs
#   2. database    → RDS MySQL Multi-AZ
#   3. compute     → ALB, ASG, Launch Template
#   4. storage     → S3 + CloudFront (Fase 3)
# ============================================================

locals {
  common_tags = {
    Project     = var.project_name
    Environment = "prod"
    ManagedBy   = "Terraform"
  }
}

# ── 1. Networking ─────────────────────────────────────────────
module "networking" {
  source = "../../modules/networking"

  project_name             = var.project_name
  vpc_cidr                 = var.vpc_cidr
  azs                      = var.azs
  public_subnet_cidrs      = var.public_subnet_cidrs
  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs
  tags                     = local.common_tags
}

# ── 2. Database ───────────────────────────────────────────────
module "database" {
  source = "../../modules/database"

  project_name   = var.project_name
  db_subnet_ids  = module.networking.private_db_subnet_ids
  sg_database_id = module.networking.sg_database_id
  db_password    = var.db_password
  multi_az       = var.multi_az
  tags           = local.common_tags
}

# ── 3. Compute ────────────────────────────────────────────────
module "compute" {
  source = "../../modules/compute"

  project_name           = var.project_name
  aws_region             = var.aws_region
  vpc_id                 = module.networking.vpc_id
  public_subnet_ids      = module.networking.public_subnet_ids
  private_app_subnet_ids = module.networking.private_app_subnet_ids
  sg_alb_id              = module.networking.sg_alb_id
  sg_backend_id          = module.networking.sg_backend_id
  rds_endpoint           = module.database.rds_endpoint
  db_password            = var.db_password
  tags                   = local.common_tags
}

# ── 4. Storage ────────────────────────────────────────────────
module "storage" {
  source       = "../../modules/storage"
  project_name = var.project_name
  tags         = local.common_tags
}
