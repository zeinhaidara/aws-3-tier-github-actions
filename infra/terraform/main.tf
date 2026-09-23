locals {
  name_prefix = "cloudbatch818-zein-${var.environment}"

  common_tags = {
    Owner       = "zein"
    Project     = "cloudbatch818"
    ManagedBy   = "terraform"
    Environment = var.environment
  }

  subnet_ids = {
    dev = {
      public   = data.terraform_remote_state.networking.outputs.dev_public_subnet_ids
      app      = data.terraform_remote_state.networking.outputs.dev_app_subnet_ids
      database = data.terraform_remote_state.networking.outputs.dev_database_subnet_ids
    }
    test = {
      public   = data.terraform_remote_state.networking.outputs.test_public_subnet_ids
      app      = data.terraform_remote_state.networking.outputs.test_app_subnet_ids
      database = data.terraform_remote_state.networking.outputs.test_database_subnet_ids
    }
    prod = {
      public   = data.terraform_remote_state.networking.outputs.prod_public_subnet_ids
      app      = data.terraform_remote_state.networking.outputs.prod_app_subnet_ids
      database = data.terraform_remote_state.networking.outputs.prod_database_subnet_ids
    }
  }

  public_subnet_ids   = local.subnet_ids[var.environment].public
  app_subnet_ids      = local.subnet_ids[var.environment].app
  database_subnet_ids = local.subnet_ids[var.environment].database
  image_uri           = var.image_tag != "" ? "${data.terraform_remote_state.networking.outputs.ecr_repository_url}:${var.image_tag}" : "${data.terraform_remote_state.networking.outputs.ecr_repository_url}@${data.aws_ecr_image.app.image_digest}"
}

data "terraform_remote_state" "networking" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "shared/networking.tfstate"
    region = var.state_region
  }
}

data "aws_ecr_image" "app" {
  repository_name = "cloudbatch818-zein-app"
  most_recent      = true
}

module "security_groups" {
  source = "./modules/security-groups"

  name_prefix = local.name_prefix
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id
  common_tags = local.common_tags
}

module "alb" {
  source = "./modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = data.terraform_remote_state.networking.outputs.vpc_id
  public_subnet_ids = local.public_subnet_ids
  security_group_id = module.security_groups.alb_security_group_id
  common_tags       = local.common_tags
}

output "security_group_ids" {
  value = {
    alb      = module.security_groups.alb_security_group_id
    app      = module.security_groups.app_security_group_id
    database = module.security_groups.database_security_group_id
  }
}

output "load_balancer_dns_name" {
  value = module.alb.load_balancer_dns_name
}

output "application_url" {
  value = "http://${module.alb.load_balancer_dns_name}"
}

output "database_endpoint" {
  value = aws_db_instance.app.address
}

output "database_master_secret_arn" {
  description = "AWS-managed Secrets Manager secret containing the RDS master credentials."
  value       = aws_db_instance.app.master_user_secret[0].secret_arn
  sensitive   = true
}

output "environment" {
  value = var.environment
}

output "name_prefix" {
  value = local.name_prefix
}

output "ecr_repository_url" {
  value = data.terraform_remote_state.networking.outputs.ecr_repository_url
}

data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-app-role" })
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "app_database_secret" {
  name = "${local.name_prefix}-database-secret-read"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
      Resource = aws_db_instance.app.master_user_secret[0].secret_arn
    }]
  })
}

resource "aws_iam_role_policy" "app_ecr_pull" {
  name = "${local.name_prefix}-ecr-pull"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = data.terraform_remote_state.networking.outputs.ecr_repository_arn
      }
    ]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/cloudbatch818/zein/${var.environment}/app"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_db_subnet_group" "app" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = local.database_subnet_ids
  tags       = merge(local.common_tags, { Name = "${local.name_prefix}-db-subnets" })
}

resource "aws_db_instance" "app" {
  identifier                  = "${local.name_prefix}-mysql"
  engine                      = "mysql"
  engine_version              = "8.0"
  instance_class              = var.rds_instance_class
  allocated_storage           = 20
  max_allocated_storage       = 50
  storage_encrypted           = true
  db_name                     = "app"
  username                    = "appadmin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.app.name
  vpc_security_group_ids      = [module.security_groups.database_security_group_id]
  publicly_accessible         = false
  skip_final_snapshot         = true
  backup_retention_period     = 1
  deletion_protection         = false
  multi_az                    = false
  apply_immediately           = true
  auto_minor_version_upgrade  = true
  copy_tags_to_snapshot       = true
  tags                        = merge(local.common_tags, { Name = "${local.name_prefix}-mysql" })
}

resource "aws_launch_template" "app" {
  name_prefix   = "${local.name_prefix}-app-"
  image_id      = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  vpc_security_group_ids = [module.security_groups.app_security_group_id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y docker
    systemctl enable --now docker
    aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin ${data.terraform_remote_state.networking.outputs.ecr_repository_url}
    docker pull ${local.image_uri}
    docker rm -f cloudbatch818-api || true
    docker run -d --restart unless-stopped --name cloudbatch818-api \
      -p 8000:8000 \
      -e DATABASE_SECRET_ARN=${aws_db_instance.app.master_user_secret[0].secret_arn} \
      -e DATABASE_HOST=${aws_db_instance.app.address} \
      -e SEED_DATA=${var.seed_data} \
      ${local.image_uri}
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${local.name_prefix}-app" })
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name_prefix}-app-asg"
  min_size                  = var.min_size
  max_size                  = var.max_size
  desired_capacity          = var.min_size
  vpc_zone_identifier       = local.app_subnet_ids
  target_group_arns         = [module.alb.target_group_arn]
  health_check_type         = "EC2"
  health_check_grace_period = 300

  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 0
      instance_warmup        = 300
    }

    triggers = ["launch_template"]
  }

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-app"
    propagate_at_launch = true
  }
}

resource "aws_cloudwatch_metric_alarm" "app_cpu_high" {
  alarm_name          = "${local.name_prefix}-app-cpu-high"
  alarm_description   = "Average CPU is high across the ${var.environment} application fleet."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }

  tags = local.common_tags
}

