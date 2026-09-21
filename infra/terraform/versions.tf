terraform {
  required_version = ">= 1.9.0"

  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Owner     = "zein"
      Project   = "cloudbatch818"
      ManagedBy = "terraform"
      Environment = var.environment
    }
  }
}
