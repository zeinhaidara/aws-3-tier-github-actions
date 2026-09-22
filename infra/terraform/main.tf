locals {
  name_prefix = "cloudbatch818-zein-${var.environment}"

  common_tags = {
    Owner       = "zein"
    Project     = "cloudbatch818"
    ManagedBy   = "terraform"
    Environment = var.environment
  }

  public_subnet_ids   = data.terraform_remote_state.networking.outputs.public_subnet_ids
  app_subnet_ids      = data.terraform_remote_state.networking.outputs.app_subnet_ids
  database_subnet_ids = data.terraform_remote_state.networking.outputs.database_subnet_ids
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
    # Amazon Linux includes Python. This deliberately has no package download
    # because the application tier has no NAT gateway in the project design.
    mkdir -p /opt/cloudbatch818-app
    echo 'ok' > /opt/cloudbatch818-app/healthz

    cat >/etc/systemd/system/cloudbatch818-app.service <<'SERVICE'
    [Unit]
    Description=Cloudbatch818 dev application placeholder
    After=network.target

    [Service]
    WorkingDirectory=/opt/cloudbatch818-app
    ExecStart=/usr/bin/python3 -m http.server 80 --directory /opt/cloudbatch818-app
    Restart=always

    [Install]
    WantedBy=multi-user.target
    SERVICE

    systemctl daemon-reload
    systemctl enable --now cloudbatch818-app.service
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

