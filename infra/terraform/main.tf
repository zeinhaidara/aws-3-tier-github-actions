locals {
  name_prefix = "cloudbatch818-zein-${var.environment}"
}

output "environment" {
  value = var.environment
}

output "name_prefix" {
  value = local.name_prefix
}
