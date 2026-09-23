variable "aws_region" {
  description = "AWS region for the environment."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Environment must be dev, test, or prod."
  }
}

variable "availability_zones" {
  description = "Two Availability Zones for the VPC."
  type        = list(string)
  default     = ["us-east-2a", "us-east-2b"]
}

variable "enable_nat_gateway" {
  description = "Enable the paid NAT Gateway path for private subnet egress."
  type        = bool
  default     = false
}

variable "state_bucket" {
  type = string
}

variable "state_region" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 1
}

variable "rds_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "image_tag" {
  type    = string
  default = ""
}

variable "seed_data" {
  type    = bool
  default = false
}
