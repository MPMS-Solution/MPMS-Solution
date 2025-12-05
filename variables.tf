variable "ssh_pub_key" {
  description = "Clé publique SSH pour se connecter aux VMs"
  type        = string
}

variable "k8s_version" {
  description = "Version de Kubernetes à installer"
  type        = string
  default     = "1.31.0"
}

variable "pod_cidr" {
  description = "CIDR des pods"
  type        = string
  default     = "10.202.0.0/16"
}
