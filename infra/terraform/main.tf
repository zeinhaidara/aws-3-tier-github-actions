locals {
  name_prefix = "cloudbatch818-zein-${var.environment}"

  common_tags = {
    Owner       = "zein"
    Project     = "cloudbatch818"
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

output "environment" {
  value = var.environment
}

output "name_prefix" {
  value = local.name_prefix
}

