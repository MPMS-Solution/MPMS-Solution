variable "os_auth_url" {
  default = "http://10.202.22.253:5000/v3"
}

variable "os_region" {
  default = "RegionOne"
}

variable "os_project_name" {
  default = "salah"
}

variable "os_username" {
  default = "salah"
}

variable "os_password" {}

variable "ssh_key_name" {
  default = "salah2-key"
}

variable "public_key_path" {
  default = "~/.ssh/salah2-key.pub"
}

variable "flavor_name" {
  default = "m1.medium"
}

variable "network_name" {
  default = "private"
}
