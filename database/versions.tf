terraform {
  required_version = ">= 1.5"

  # Remote state in de S3 bucket uit de handleiding. De bucketnaam geef je mee bij init:
  #   terraform init -backend-config="bucket=<jouw-state-bucket>"
  # De database heeft een eigen state-key, zodat de pipeline (infra/) hem nooit kan verwijderen.
  backend "s3" {
    key     = "database/terraform.tfstate"
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

provider "aws" {
  region = var.region
}
