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

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

locals {
  name      = "cloudbatch818-zein-${var.environment}-eks"
  image_uri = var.image_tag != "" ? "${data.terraform_remote_state.networking.outputs.ecr_repository_url}:${var.image_tag}" : "${data.terraform_remote_state.networking.outputs.ecr_repository_url}@${data.aws_ecr_image.app.image_digest}"
  app_subnet_ids = {
    dev  = data.terraform_remote_state.networking.outputs.dev_app_subnet_ids
    test = data.terraform_remote_state.networking.outputs.test_app_subnet_ids
    prod = data.terraform_remote_state.networking.outputs.prod_app_subnet_ids
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = "1.31"

  vpc_id     = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_ids = local.app_subnet_ids[var.environment]

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  tags = {
    Owner       = "zein"
    Project     = "cloudbatch818"
    ManagedBy   = "terraform"
    Environment = var.environment
    Workload    = "eks"
  }

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    app = {
      iam_role_name  = "${local.name}-node-role"
      instance_types = ["t3.small"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
      subnet_ids     = local.app_subnet_ids[var.environment]
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "database_from_eks" {
  security_group_id            = data.terraform_remote_state.environment.outputs.security_group_ids.database
  referenced_security_group_id = module.eks.node_security_group_id
  description                  = "Allow MySQL from the EKS node group"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
}

resource "kubernetes_namespace" "app" {
  metadata { name = "cloudbatch818" }

  depends_on = [module.eks]
}

resource "aws_iam_role" "app" {
  name = "${local.name}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:cloudbatch818:cloudbatch818-api"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "app_secret" {
  name = "${local.name}-secret-read"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:DescribeSecret", "secretsmanager:GetSecretValue"]
      Resource = data.terraform_remote_state.environment.outputs.database_master_secret_arn
    }]
  })
}

resource "kubernetes_service_account" "app" {
  metadata {
    name      = "cloudbatch818-api"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.app.arn
    }
  }
}

resource "kubernetes_deployment" "app" {
  metadata {
    name      = "cloudbatch818-api"
    namespace = kubernetes_namespace.app.metadata[0].name
  }
  spec {
    replicas = 1
    selector { match_labels = { app = "cloudbatch818-api" } }
    template {
      metadata { labels = { app = "cloudbatch818-api" } }
      spec {
        service_account_name = kubernetes_service_account.app.metadata[0].name

        container {
          name  = "api"
          image = local.image_uri
          port { container_port = 8000 }
          env {
            name  = "AWS_REGION"
            value = var.aws_region
          }
          env {
            name  = "AWS_DEFAULT_REGION"
            value = var.aws_region
          }
          env {
            name  = "DATABASE_SECRET_ARN"
            value = data.terraform_remote_state.environment.outputs.database_master_secret_arn
          }
          env {
            name  = "DATABASE_HOST"
            value = data.terraform_remote_state.environment.outputs.database_endpoint
          }
          env {
            name  = "SEED_DATA"
            value = "true"
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8000
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "app" {
  metadata {
    name      = "cloudbatch818-api"
    namespace = kubernetes_namespace.app.metadata[0].name
    annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
    }
  }
  spec {
    selector = { app = "cloudbatch818-api" }
    port {
      port        = 80
      target_port = 8000
    }
    type = "LoadBalancer"
  }
}
