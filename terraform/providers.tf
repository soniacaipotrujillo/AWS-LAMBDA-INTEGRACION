# providers.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # Esto agregará etiquetas automáticas a TODO lo que creemos
  default_tags {
    tags = {
      Environment = terraform.workspace
      Project     = "ImageProcessor"
      ManagedBy   = "Terraform"
    }
  }
}