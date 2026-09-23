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
  type    = string
  default = ""
}

variable "desired_count" {
  type    = number
  default = 1
}
