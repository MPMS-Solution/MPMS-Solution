variable "cp_count" {
  description = "Nombre de noeuds control plane"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Nombre de noeuds worker"
  type        = number
  default     = 3
}

variable "flavor_name" {
  description = "Flavor OpenStack pour les VMs"
  type        = string
  default     = "m1.medium"
}

variable "image_name" {
  description = "Nom de l'image OpenStack"
  type        = string
  default     = "Ubuntu-22.04"
}

variable "keypair_name" {
  description = "Nom de la keypair SSH"
  type        = string
  default     = "terraform"
}

variable "network_name" {
  description = "Nom du reseau OpenStack"
  type        = string
  default     = "public"
}

variable "volume_size" {
  description = "Taille des volumes de donnees en Go"
  type        = number
  default     = 8
}

variable "allowed_address_cidr" {
  description = "CIDR pour les allowed address pairs (MetalLB, Cilium)"
  type        = string
  default     = "10.202.0.0/16"
}

variable "metallb_ip_range" {
  description = "Plage d'IPs pour MetalLB"
  type        = string
  default     = "10.202.20.10-10.202.20.20"
}

variable "ssh_private_key_path" {
  description = "Chemin vers la cle privee SSH pour les provisioners"
  type        = string
  default     = "/home/test/id_ed25519"
}

variable "ssh_allowed_cidr" {
  description = "CIDR autorise pour l'acces SSH (restreindre en production)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "k8s_api_allowed_cidr" {
  description = "CIDR autorise pour l'acces a l'API Kubernetes (restreindre en production)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "github_pat" {
  description = "GitHub Personal Access Token pour ArgoCD (repo prive)"
  type        = string
  sensitive   = true
}

variable "rook_volume_size" {
  description = "Taille des volumes Rook-Ceph en Go (un par worker)"
  type        = number
  default     = 20
}

variable "minio_access_key" {
  description = "MinIO access key pour Velero"
  type        = string
  default     = "minioadmin"
}

variable "minio_secret_key" {
  description = "MinIO secret key pour Velero"
  type        = string
  sensitive   = true
  default     = "minioadmin"
}

variable "pihole_password" {
  description = "Mot de passe admin Pi-hole"
  type        = string
  sensitive   = true
  default     = "admin"
}

variable "grafana_password" {
  description = "Mot de passe admin Grafana"
  type        = string
  sensitive   = true
  default     = "admin"
}