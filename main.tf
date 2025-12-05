terraform {
  required_version = ">= 1.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53"
    }
  }
}
provider "openstack" {
  auth_url    = "http://10.202.22.253:5000/v3"
  user_name   = "salah"
  password    = "salah"
  domain_name = "Default"
  region      = "RegionOne"
  tenant_name = "salah"
}

# Security group
resource "openstack_networking_secgroup_v2" "k8s_secgroup" {
  name        = "k8s-secgroup"
  description = "Security group for Kubernetes cluster"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# Control Plane
resource "openstack_compute_instance_v2" "master" {
  name       = "k8s-master"
  image_name = "Ubuntu-22.04-MLOPINTO"
  flavor_name = "m1.small"
  key_pair    = "salah2-key"
  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]

  network {
    name = "public"
  }

  user_data = templatefile("${path.module}/cloudinit-master.yaml", {
    SSH_PUB_KEY = var.ssh_pub_key
    POD_CIDR    = var.pod_cidr
    K8S_VERSION = var.k8s_version
  })
}

# Worker Node
resource "openstack_compute_instance_v2" "worker" {
  name       = "k8s-worker"
  image_name = "Ubuntu-22.04-MLOPINTO"
  flavor_name = "m1.small"
  key_pair    = "salah2-key"
  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]

  network {
    name = "public"
  }

  user_data = templatefile("${path.module}/cloudinit-worker.yaml", {
    SSH_PUB_KEY = var.ssh_pub_key
  })
}
