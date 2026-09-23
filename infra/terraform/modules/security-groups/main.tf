resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb-sg"
  description = "ALB ingress for ${var.name_prefix}"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP for the initial lab listener"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from the internet"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "ALB outbound traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-alb-sg" })
}

resource "aws_security_group" "app" {
  name        = "${var.name_prefix}-app-sg"
  description = "Application tier access for ${var.name_prefix}"
  vpc_id      = var.vpc_id

  ingress {
    description     = "FastAPI from the ALB"
    protocol        = "tcp"
    from_port       = 8000
    to_port         = 8000
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Application outbound access for ECR, RDS, and updates"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-app-sg" })
}

resource "aws_security_group" "database" {
  name        = "${var.name_prefix}-database-sg"
  description = "Database tier access for ${var.name_prefix}"
  vpc_id      = var.vpc_id

  ingress {
    description     = "MySQL from the application tier"
    protocol        = "tcp"
    from_port       = 3306
    to_port         = 3306
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description = "Database response traffic"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.name_prefix}-database-sg" })
}
