terraform {
  required_version = ">= 1.5"

  # Remote state in de S3 bucket uit de handleiding. De bucketnaam geef je mee bij init:
  #   terraform init -backend-config="bucket=<jouw-state-bucket>"
  backend "s3" {
    key     = "infra/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.66.0"
    }
  }
}

# Geen profile meer: CloudShell en GitHub Actions leveren de credentials via environment variabelen.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "SaxIT"
      ManagedBy = "Terraform"
    }
  }
}
