terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.49.0"
    }
  }
}

provider "openstack" {
  auth_url    = var.os_auth_url
  region      = var.os_region
  tenant_name = var.os_project_name
  user_name   = var.os_username
  password    = var.os_password
  domain_name = "default"
}
