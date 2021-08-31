variable "region" {
  type        = string
  description = "AWS Region where to provision VPC Network"
}

variable "profile" {
  type = string
}

variable "allow_port_list" {
  description = "List of Ports to open for server"
  type        = list(string)
  default     = ["22", "443"]
}

variable "vpc_cidr" {
  description = "vpc cidr block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "bucket_name" {
  type = string
}
