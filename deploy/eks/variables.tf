variable "aws_region" { type = string }
variable "environment" {
  type    = string
  default = "dev"
  validation {
    condition     = var.environment == "dev"
    error_message = "This lab EKS deployment is limited to dev."
  }
}
variable "state_bucket" { type = string }
variable "state_region" { type = string }
variable "image_tag" {
  type    = string
  default = ""
}
