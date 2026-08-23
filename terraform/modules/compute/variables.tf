variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "public_subnet_ids" {
  type = list(string)
}

variable "private_subnet_ids" {
  type = list(string)
}