locals {
  common_tags = {
    Owner       = "zein"
    Project     = "cloudbatch818"
    ManagedBy   = "terraform"
    Environment = "shared"
  }
}

module "networking" {
  source = "../modules/networking"

  name_prefix           = "cloudbatch818-zein-shared"
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  app_subnet_cidrs      = var.app_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  enable_nat_gateway    = var.enable_nat_gateway
  common_tags           = local.common_tags
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "public_subnet_ids" {
  value = module.networking.public_subnet_ids
}

output "app_subnet_ids" {
  value = module.networking.app_subnet_ids
}

output "database_subnet_ids" {
  value = module.networking.database_subnet_ids
}
