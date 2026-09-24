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
  create_kms_key                           = false
  cluster_encryption_config = {
    provider_key_arn = ""
    resources        = []
  }

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

resource "kubernetes_namespace" "app" {
  metadata { name = "cloudbatch818" }
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
