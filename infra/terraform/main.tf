locals {
  name_prefix = "cloudbatch818-zein-${var.environment}"

  common_tags = {
    Owner       = "zein"
    Project     = "cloudbatch818"
    ManagedBy   = "terraform"
    Environment = var.environment
  }
}

data "terraform_remote_state" "networking" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "shared/networking.tfstate"
    region = var.state_region
  }
}

module "security_groups" {
  source = "./modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id
  common_tags = local.common_tags
}

output "security_group_ids" {
  value = {
    alb      = module.security_groups.alb_security_group_id
    app      = module.security_groups.app_security_group_id
    database = module.security_groups.database_security_group_id
  }
}

output "environment" {
  value = var.environment
}

output "name_prefix" {
  value = local.name_prefix
}

