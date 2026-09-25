locals {
  name_prefix = "cloudbatch818-zein-${var.environment}-ecs"
  image_uri   = "${data.terraform_remote_state.networking.outputs.ecr_repository_url}:${var.image_tag}"
  public_subnet_ids = {
    dev  = data.terraform_remote_state.networking.outputs.dev_public_subnet_ids
    test = data.terraform_remote_state.networking.outputs.test_public_subnet_ids
    prod = data.terraform_remote_state.networking.outputs.prod_public_subnet_ids
  }
  app_subnet_ids = {
    dev  = data.terraform_remote_state.networking.outputs.dev_app_subnet_ids
    test = data.terraform_remote_state.networking.outputs.test_app_subnet_ids
    prod = data.terraform_remote_state.networking.outputs.prod_app_subnet_ids
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

data "terraform_remote_state" "environment" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "${var.environment}/terraform.tfstate"
    region = var.state_region
  }
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/cloudbatch818/zein/${var.environment}/ecs"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "app" {
  name = "${local.name_prefix}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_iam_role" "execution" {
  name = "${local.name_prefix}-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name = "${local.name_prefix}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "task_secret" {
  name = "${local.name_prefix}-secret-read"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
      Resource = data.terraform_remote_state.environment.outputs.database_master_secret_arn
    }]
  })
}

module "alb" {
  source = "../../infra/terraform/modules/alb"

  name_prefix       = local.name_prefix
  vpc_id            = data.terraform_remote_state.networking.outputs.vpc_id
  public_subnet_ids = local.public_subnet_ids[var.environment]
  security_group_id = data.terraform_remote_state.environment.outputs.security_group_ids.alb
  domain_name       = var.domain_name
  hosted_zone_name  = var.hosted_zone_name
  target_type       = "ip"
  target_port       = 8000
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = local.image_uri
    essential = true

    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
      protocol      = "tcp"
    }]

    healthCheck = {
      command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8000/healthz', timeout=2)\" || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }

    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "AWS_DEFAULT_REGION", value = var.aws_region },
      { name = "DATABASE_SECRET_ARN", value = data.terraform_remote_state.environment.outputs.database_master_secret_arn },
      { name = "DATABASE_HOST", value = data.terraform_remote_state.environment.outputs.database_endpoint },
      { name = "SEED_DATA", value = var.environment == "dev" ? "true" : "false" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.app.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "app" {
  name            = "${local.name_prefix}-service"
  cluster         = aws_ecs_cluster.app.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = local.app_subnet_ids[var.environment]
    security_groups  = [data.terraform_remote_state.environment.outputs.security_group_ids.app]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_group_arn
    container_name   = "api"
    container_port   = 8000
  }

  depends_on = [module.alb]
}

resource "aws_cloudwatch_metric_alarm" "service_cpu" {
  alarm_name          = "${local.name_prefix}-cpu-high"
  alarm_description   = "High average ECS service CPU utilization."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    ClusterName = aws_ecs_cluster.app.name
    ServiceName = aws_ecs_service.app.name
  }
}

resource "aws_cloudwatch_metric_alarm" "service_running_tasks" {
  alarm_name          = "${local.name_prefix}-running-tasks-low"
  alarm_description   = "ECS service has fewer running tasks than desired."
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.desired_count
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  dimensions = {
    ClusterName = aws_ecs_cluster.app.name
    ServiceName = aws_ecs_service.app.name
  }
}
