output "control_plane_ip" {
  value = openstack_networking_floatingip_v2.cp1_fip.address
}

output "worker1_internal_ip" {
  value = openstack_compute_instance_v2.worker1.network[0].fixed_ip_v4
}
