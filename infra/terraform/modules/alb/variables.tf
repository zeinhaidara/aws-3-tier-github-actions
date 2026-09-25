variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "acm_certificate_arn" {
  type    = string
  default = ""
}

variable "domain_name" {
  type    = string
  default = ""
}

variable "hosted_zone_name" {
  type    = string
  default = ""
}

variable "target_type" {
  type    = string
  default = "instance"
}

variable "target_port" {
  type    = number
  default = 8000
}

variable "health_check_path" {
  type    = string
  default = "/healthz"
}
