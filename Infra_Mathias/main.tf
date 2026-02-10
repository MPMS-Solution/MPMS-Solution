terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9.1"
    }
  }
}

# --- DATA SOURCES ---
data "openstack_networking_network_v2" "public" {
  name = "public"
}

data "openstack_images_image_v2" "ubuntu" {
  most_recent = true
  name        = "Ubuntu-22.04"
}

data "openstack_compute_keypair_v2" "default" {
  name = "terraform"
}

# --- SECURITY GROUPS ---
resource "openstack_networking_secgroup_v2" "k8s_secgroup" {
  name        = "k8s-sg"
  description = "Security group for Kubernetes cluster"
}

resource "openstack_networking_secgroup_rule_v2" "rules" {
  for_each          = toset(["22", "6443", "80", "443"])
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = each.value
  port_range_max    = each.value
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.k8s_secgroup.id
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# --- PORTS ---
resource "openstack_networking_port_v2" "cp_ports" {
  count              = 3
  name               = "port-k8s-cp${count.index + 1}"
  network_id         = data.openstack_networking_network_v2.public.id
  security_group_ids = [openstack_networking_secgroup_v2.k8s_secgroup.id]
  allowed_address_pairs {
    ip_address = "10.202.0.0/16"
  }
}

resource "openstack_networking_port_v2" "worker_ports" {
  count              = 3
  name               = "port-k8s-worker${count.index + 1}"
  network_id         = data.openstack_networking_network_v2.public.id
  security_group_ids = [openstack_networking_secgroup_v2.k8s_secgroup.id]
  allowed_address_pairs {
    ip_address = "10.202.0.0/16"
  }
}

# --- VOLUMES ---
resource "openstack_blockstorage_volume_v3" "cp_data" {
  count = 3
  name  = "v-cp${count.index + 1}"
  size  = 8
}

resource "openstack_blockstorage_volume_v3" "wk_data" {
  count = 3
  name  = "v-wk${count.index + 1}"
  size  = 8
}

resource "openstack_blockstorage_volume_v3" "rook_data" {
  count = 3
  name  = "v-rk${count.index + 1}"
  size  = 20
}

# --- INSTANCES ---
resource "openstack_compute_instance_v2" "cp" {
  count        = 3
  name         = "k8s-cp${count.index + 1}"
  flavor_name  = "m1.small"
  key_pair     = data.openstack_compute_keypair_v2.default.name
  image_id     = data.openstack_images_image_v2.ubuntu.id
  config_drive = true
  network {
    port = openstack_networking_port_v2.cp_ports[count.index].id
  }
  user_data = count.index == 0 ? templatefile("${path.module}/cloud-init/cp1.yaml", {
    control_plane_ip = openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0],
    minio_access_key = "admin",
    minio_secret_key = "password"
  }) : templatefile("${path.module}/cloud-init/worker.yaml", {
    control_plane_ip = openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]
  })
}

resource "openstack_compute_instance_v2" "worker" {
  count        = 3
  name         = "k8s-worker${count.index + 1}"
  flavor_name  = "m1.small"
  key_pair     = data.openstack_compute_keypair_v2.default.name
  image_id     = data.openstack_images_image_v2.ubuntu.id
  config_drive = true
  network {
    port = openstack_networking_port_v2.worker_ports[count.index].id
  }
  user_data = templatefile("${path.module}/cloud-init/worker.yaml", {
    control_plane_ip = openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]
  })
}

# --- ATTACHMENTS ---
resource "openstack_compute_volume_attach_v2" "cp_v_attach" {
  count       = 3
  instance_id = openstack_compute_instance_v2.cp[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.cp_data[count.index].id
}

resource "openstack_compute_volume_attach_v2" "wk_v_attach" {
  count       = 3
  instance_id = openstack_compute_instance_v2.worker[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.wk_data[count.index].id
}

resource "openstack_compute_volume_attach_v2" "rk_v_attach" {
  count       = 3
  instance_id = openstack_compute_instance_v2.worker[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.rook_data[count.index].id
}

# --- JOIN PROCESS ---
resource "time_sleep" "wait_for_cp_boot" {
  create_duration = "1m"
  depends_on      = [openstack_compute_instance_v2.cp[0]]
}

resource "null_resource" "join" {
  count      = 5
  depends_on = [time_sleep.wait_for_cp_boot]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/id_ed25519")
    timeout     = "15m"
    host        = count.index < 2 ? openstack_networking_port_v2.cp_ports[count.index + 1].all_fixed_ips[0] : openstack_networking_port_v2.worker_ports[count.index - 2].all_fixed_ips[0]
  }

  provisioner "file" {
    source      = "~/.ssh/id_ed25519"
    destination = "/home/ubuntu/.ssh/id_ed25519"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 600 /home/ubuntu/.ssh/id_ed25519",
      "while ! ssh -i /home/ubuntu/.ssh/id_ed25519 -o StrictHostKeyChecking=no ubuntu@${openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]} 'sudo test -f /root/cloud-init-complete' 2>/dev/null; do echo 'Waiting for CP1...'; sleep 10; done",
      count.index < 2 ? "ssh -i /home/ubuntu/.ssh/id_ed25519 -o StrictHostKeyChecking=no ubuntu@${openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]} 'sudo cat /root/join-cp.sh' | sed 's/kubeadm join/kubeadm join --ignore-preflight-errors=NumCPU/' | sudo bash" : "ssh -i /home/ubuntu/.ssh/id_ed25519 -o StrictHostKeyChecking=no ubuntu@${openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]} 'sudo cat /root/join-worker.sh' | sudo bash"
    ]
  }
}