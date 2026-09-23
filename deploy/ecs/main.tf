locals {
  name_prefix = "cloudbatch818-zein-${var.environment}-ecs"
  image_uri   = var.image_tag != "" ? "${data.terraform_remote_state.networking.outputs.ecr_repository_url}:${var.image_tag}" : "${data.terraform_remote_state.networking.outputs.ecr_repository_url}@${data.aws_ecr_image.app.image_digest}"
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

data "aws_ecr_image" "app" {
  repository_name = "cloudbatch818-zein-app"
  most_recent     = true
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

resource "aws_lb" "app" {
  name                       = substr(local.name_prefix, 0, 32)
  internal                   = false
  load_balancer_type         = "application"
  drop_invalid_header_fields = true
  security_groups            = [data.terraform_remote_state.environment.outputs.security_group_ids.alb]
  subnets                    = data.terraform_remote_state.networking.outputs.dev_public_subnet_ids
}

resource "aws_lb_target_group" "app" {
  name_prefix = "ecs-"
  port        = 8000
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.terraform_remote_state.networking.outputs.vpc_id

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.name_prefix
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn        = aws_iam_role.execution.arn
  task_role_arn             = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "api"
    image     = local.image_uri
    essential = true

    portMappings = [{
      containerPort = 8000
      hostPort      = 8000
      protocol      = "tcp"
    }]

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

  network_configuration {
    subnets          = data.terraform_remote_state.networking.outputs.dev_app_subnet_ids
    security_groups  = [data.terraform_remote_state.environment.outputs.security_group_ids.app]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "api"
    container_port    = 8000
  }

  depends_on = [aws_lb_listener.http]
}
