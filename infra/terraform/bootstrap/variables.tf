variable "aws_region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Lowercase project identifier used in resource names."
  type        = string
  default     = "cloudbatch818-zein-aws-3-tier"
}
