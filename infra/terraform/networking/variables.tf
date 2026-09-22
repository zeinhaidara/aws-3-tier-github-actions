variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-2a", "us-east-2b"]
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "app_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.11.0/24", "10.20.12.0/24"]
}

variable "database_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.21.0/24", "10.20.22.0/24"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
}

variable "test_public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.31.0/24", "10.20.32.0/24"]
}

variable "test_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.41.0/24", "10.20.42.0/24"]
}

variable "test_database_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.51.0/24", "10.20.52.0/24"]
}

variable "prod_public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.61.0/24", "10.20.62.0/24"]
}

variable "prod_app_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.71.0/24", "10.20.72.0/24"]
}

variable "prod_database_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.81.0/24", "10.20.82.0/24"]
}
