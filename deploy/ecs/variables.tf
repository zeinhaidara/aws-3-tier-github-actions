variable "aws_region" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "state_bucket" {
  type = string
}

variable "state_region" {
  type = string
}

variable "image_tag" {
  description = "Immutable ECR image tag, normally sha-<commit>."
  type        = string
}

variable "domain_name" {
  description = "Optional public hostname for ECS, e.g. ecs-dev.example.com. The Route 53 hosted zone must already exist."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Public Route 53 hosted zone name, e.g. example.com."
  type        = string
  default     = ""

  validation {
    condition     = (var.domain_name == "" && var.hosted_zone_name == "") || (var.domain_name != "" && var.hosted_zone_name != "")
    error_message = "domain_name and hosted_zone_name must either both be set or both be empty."
  }
}

variable "desired_count" {
  type    = number
  default = 1
}
