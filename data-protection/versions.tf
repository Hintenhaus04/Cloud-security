terraform {
  required_version = ">= 1.5"

  #   terraform init -backend-config="bucket=<jouw-state-bucket>"
  backend "s3" {
    key     = "data-protection/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "SaxIT"
      ManagedBy = "Terraform"
    }
  }
}
