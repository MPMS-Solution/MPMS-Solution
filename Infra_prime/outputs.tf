output "cp_ips" {
  description = "Adresses IP des noeuds control plane"
  value       = [for port in openstack_networking_port_v2.cp_ports : port.all_fixed_ips[0]]
}

output "worker_ips" {
  description = "Adresses IP des noeuds worker"
  value       = [for port in openstack_networking_port_v2.worker_ports : port.all_fixed_ips[0]]
}

output "cp1_ip" {
  description = "Adresse IP du premier control plane (API server)"
  value       = openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]
}

output "ssh_command_cp1" {
  description = "Commande SSH pour se connecter au CP1"
  value       = "ssh ubuntu@${openstack_networking_port_v2.cp_ports[0].all_fixed_ips[0]}"
}

output "cluster_status" {
  description = "Statut du bootstrap"
  value       = "Cluster entièrement déployé. Exécuter 'sudo /root/check-cluster.sh' sur CP1 pour le détail."
  depends_on  = [null_resource.wait_for_full_bootstrap]
}