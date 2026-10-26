terraform {
  required_version = ">= 1.5"

  #   terraform init -backend-config="bucket=<jouw-state-bucket>"
  # Eigen state: de logstream blijft bestaan als de pipeline infra/ opnieuw uitrolt.
  backend "s3" {
    key     = "monitoring/terraform.tfstate"
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

variable "region" {
  type    = string
  default = "us-east-1"
}
