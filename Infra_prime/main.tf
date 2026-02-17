terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}

# --- Data Sources ---
data "openstack_networking_network_v2" "public" {
  name = var.network_name
}

data "openstack_images_image_v2" "ubuntu" {
  most_recent = true
  name        = var.image_name
}

data "openstack_compute_keypair_v2" "default" {
  name = var.keypair_name
}

# --- SECURITY GROUPS ---
resource "openstack_networking_secgroup_v2" "k8s_secgroup" {
  name        = "k8s-sg"
  description = "Security group for Kubernetes cluster"
}

resource "openstack_networking_secgroup_rule_v2" "ssh_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "k8s_api_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = var.k8s_api_allowed_cidr
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "internal_rule" {
  description       = "Allow all internal traffic"
  direction         = "ingress"
  ethertype         = "IPv4"
  remote_group_id   = openstack_networking_secgroup_v2.k8s_secgroup.id
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "http_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "https_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "icmp_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "icmp"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "dns_tcp_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

resource "openstack_networking_secgroup_rule_v2" "dns_udp_rule" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "udp"
  port_range_min    = 53
  port_range_max    = 53
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.k8s_secgroup.id
}

# --- PORTS ---
resource "openstack_networking_port_v2" "cp_ports" {
  count              = var.cp_count
  name               = "port-k8s-cp${count.index + 1}"
  network_id         = data.openstack_networking_network_v2.public.id
  security_group_ids = [openstack_networking_secgroup_v2.k8s_secgroup.id]

  allowed_address_pairs {
    ip_address = var.allowed_address_cidr
  }
}

resource "openstack_networking_port_v2" "worker_ports" {
  count              = var.worker_count
  name               = "port-k8s-worker${count.index + 1}"
  network_id         = data.openstack_networking_network_v2.public.id
  security_group_ids = [openstack_networking_secgroup_v2.k8s_secgroup.id]

  allowed_address_pairs {
    ip_address = var.allowed_address_cidr
  }
}

# --- VOLUMES ---
resource "openstack_blockstorage_volume_v3" "cp_data" {
  count = var.cp_count
  name  = "k8s-cp${count.index + 1}-data"
  size  = var.volume_size
}

resource "openstack_blockstorage_volume_v3" "worker_data" {
  count = var.worker_count
  name  = "k8s-worker${count.index + 1}-data"
  size  = var.volume_size
}

# Volumes dédiés Rook-Ceph (un par worker, 20 Go)
resource "openstack_blockstorage_volume_v3" "rook_data" {
  count = var.worker_count
  name  = "k8s-worker${count.index + 1}-rook"
  size  = var.rook_volume_size
}

# --- CONTROL PLANES ---
resource "openstack_compute_instance_v2" "cp" {
  count        = var.cp_count
  name         = "k8s-cp${count.index + 1}"
  flavor_name  = var.flavor_name
  key_pair     = data.openstack_compute_keypair_v2.default.name
  image_id     = data.openstack_images_image_v2.ubuntu.id
  config_drive = true

  network {
    port = openstack_networking_port_v2.cp_ports[count.index].id
  }

  user_data = count.index == 0 ? templatefile("${path.module}/cloud-init/cp1.yaml", {
    control_plane_ip = openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]
    github_pat       = var.github_pat
    minio_access_key = var.minio_access_key
    minio_secret_key = var.minio_secret_key
    pihole_password  = var.pihole_password
    grafana_password = var.grafana_password
    }) : templatefile("${path.module}/cloud-init/worker.yaml", {
    control_plane_ip = openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]
  })
}

resource "openstack_compute_volume_attach_v2" "cp_volume_attach" {
  count       = var.cp_count
  instance_id = openstack_compute_instance_v2.cp[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.cp_data[count.index].id
}

# --- WORKER NODES ---
resource "openstack_compute_instance_v2" "worker" {
  count        = var.worker_count
  name         = "k8s-worker${count.index + 1}"
  flavor_name  = var.flavor_name
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

resource "openstack_compute_volume_attach_v2" "worker_volume_attach" {
  count       = var.worker_count
  instance_id = openstack_compute_instance_v2.worker[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.worker_data[count.index].id
}

# Volumes Rook-Ceph attachés aux workers
resource "openstack_compute_volume_attach_v2" "rook_volume_attach" {
  count       = var.worker_count
  instance_id = openstack_compute_instance_v2.worker[count.index].id
  volume_id   = openstack_blockstorage_volume_v3.rook_data[count.index].id
}

# --- ATTENTE ACTIVE : SCRIPTS DE JOIN SUR CP1 ---
resource "null_resource" "wait_for_cp1_join_scripts" {
  depends_on = [openstack_compute_instance_v2.cp[0]]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Connecte a CP1, attente des scripts de join...'",
      "while ! sudo test -f /root/join-worker.sh || ! sudo test -f /root/join-cp.sh; do sleep 5; done",
      "echo 'Scripts de join prets!'"
    ]
  }
}

# --- JOINTURE CP ---
resource "null_resource" "cp_join" {
  count      = var.cp_count - 1
  depends_on = [null_resource.wait_for_cp1_join_scripts]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = openstack_networking_port_v2.cp_ports[count.index + 1].all_fixed_ips[0]
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "while ! sudo test -f /root/cloud-init-complete; do sleep 5; done"
    ]
  }

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@${openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]} 'sudo cat /root/join-cp.sh' | sed 's/kubeadm join/kubeadm join --ignore-preflight-errors=NumCPU/' | ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@${openstack_networking_port_v2.cp_ports[count.index + 1].all_fixed_ips[0]} 'sudo bash'"
  }
}

# --- JOINTURE WORKERS ---
resource "null_resource" "worker_join" {
  count      = var.worker_count
  depends_on = [null_resource.wait_for_cp1_join_scripts]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file(var.ssh_private_key_path)
    host        = openstack_networking_port_v2.worker_ports[count.index].all_fixed_ips[0]
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "while ! sudo test -f /root/cloud-init-complete; do sleep 5; done"
    ]
  }

  provisioner "local-exec" {
    command = "ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@${openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]} 'sudo cat /root/join-worker.sh' | ssh -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@${openstack_networking_port_v2.worker_ports[count.index].all_fixed_ips[0]} 'sudo bash'"
  }
}