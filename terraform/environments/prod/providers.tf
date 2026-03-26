terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  # Backend S3 con locking nativo (Terraform >= 1.10)
  # use_lockfile = true escribe un archivo .tflock en el mismo bucket
  # usando S3 conditional writes — sin DynamoDB, sin costo adicional.
  # EJECUTAR scripts/bootstrap.ps1 ANTES de terraform init
  backend "s3" {
    bucket       = "aws-3tier-appcitas-tfstate"
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-3tier-enterprise"
      Environment = "prod"
      ManagedBy   = "Terraform"
      Repository  = "github.com/carlossanchezcloud/aws-3tier-enterprise"
    }
  }
}
