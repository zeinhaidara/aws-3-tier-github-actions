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

locals {
  additional_subnets = {
    test_public = {
      cidrs = var.test_public_subnet_cidrs
      tier  = "public"
    }
    test_app = {
      cidrs = var.test_app_subnet_cidrs
      tier  = "application"
    }
    test_database = {
      cidrs = var.test_database_subnet_cidrs
      tier  = "database"
    }
    prod_public = {
      cidrs = var.prod_public_subnet_cidrs
      tier  = "public"
    }
    prod_app = {
      cidrs = var.prod_app_subnet_cidrs
      tier  = "application"
    }
    prod_database = {
      cidrs = var.prod_database_subnet_cidrs
      tier  = "database"
    }
  }

  additional_subnet_instances = merge([
    for group_name, group in local.additional_subnets : {
      for index, cidr in group.cidrs : "${group_name}-${index + 1}" => {
        cidr = cidr
        az   = var.availability_zones[index]
        tier = group.tier
        name = "${group_name}-${index + 1}"
      }
    }
  ]...)
}

resource "aws_subnet" "additional" {
  for_each = local.additional_subnet_instances

  vpc_id            = module.networking.vpc_id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = merge(local.common_tags, {
    Name        = "cloudbatch818-zein-${each.value.name}"
    Tier        = each.value.tier
    Environment = startswith(each.key, "test") ? "test" : "prod"
  })
}

resource "aws_route_table_association" "additional_public" {
  for_each = {
    for key, subnet in local.additional_subnet_instances : key => subnet
    if subnet.tier == "public"
  }

  subnet_id      = aws_subnet.additional[each.key].id
  route_table_id = module.networking.public_route_table_id
}

resource "aws_route_table_association" "additional_private" {
  for_each = {
    for key, subnet in local.additional_subnet_instances : key => subnet
    if subnet.tier != "public"
  }

  subnet_id      = aws_subnet.additional[each.key].id
  route_table_id = module.networking.private_route_table_id
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

output "test_public_subnet_ids" {
  value = [for key, subnet in aws_subnet.additional : subnet.id if startswith(key, "test_public-")]
}

output "test_app_subnet_ids" {
  value = [for key, subnet in aws_subnet.additional : subnet.id if startswith(key, "test_app-")]
}

output "test_database_subnet_ids" {
  value = [for key, subnet in aws_subnet.additional : subnet.id if startswith(key, "test_database-")]
}

output "prod_public_subnet_ids" {
  value = [for key, subnet in aws_subnet.additional : subnet.id if startswith(key, "prod_public-")]
}

output "prod_app_subnet_ids" {
  value = [for key, subnet in aws_subnet.additional : subnet.id if startswith(key, "prod_app-")]
}

output "prod_database_subnet_ids" {
  value = [for key, subnet in aws_subnet.additional : subnet.id if startswith(key, "prod_database-")]
}
