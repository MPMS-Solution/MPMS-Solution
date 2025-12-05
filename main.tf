##########################
# LOAD EXISTING SSH KEYPAIR
##########################

data "openstack_compute_keypair_v2" "ssh_key" {
  name = var.ssh_key_name
}

##########################
# FIND UBUNTU IMAGE AUTOMATICALLY
##########################

data "openstack_images_image_v2" "ubuntu" {
  most_recent = true

  properties = {
    os_distro = "ubuntu"
  }
}

##########################
# SECURITY GROUP
##########################

resource "openstack_networking_secgroup_v2" "k8s_secgroup" {
  name        = "k8s-secgroup"
  description = "Security group for Kubernetes cluster"
}

locals {
  k8s_ports = [
    { port = 22,    proto = "tcp" },
    { port = 6443,  proto = "tcp" },
    { port = 2379,  proto = "tcp" },
    { port = 2380,  proto = "tcp" },
    { port = 10250, proto = "tcp" }
  ]
}

resource "openstack_networking_secgroup_rule_v2" "k8s_rules" {
  for_each = { for p in local.k8s_ports : p.port => p }

  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.proto
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

#######################################
# CONTROL PLANE VM
#######################################

resource "openstack_compute_instance_v2" "cp1" {
  name        = "cp1"
  image_id    = data.openstack_images_image_v2.ubuntu.id
  flavor_name = var.flavor_name
  key_pair    = var.ssh_key_name

  network {
    name = var.network_name
  }

  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]
}

resource "openstack_networking_floatingip_v2" "cp1_fip" {
  pool = "public"
}

resource "openstack_networking_floatingip_associate_v2" "cp1_attach" {
  floating_ip = openstack_networking_floatingip_v2.cp1_fip.address
  port_id     = openstack_compute_instance_v2.cp1.network[0].port
}

#######################################
# WORKER VM
#######################################

resource "openstack_compute_instance_v2" "worker1" {
  name        = "worker1"
  image_id    = data.openstack_images_image_v2.ubuntu.id
  flavor_name = var.flavor_name
  key_pair    = var.ssh_key_name

  network {
    name = var.network_name
  }

  security_groups = [openstack_networking_secgroup_v2.k8s_secgroup.name]
}
