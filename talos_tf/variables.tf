variable "node_name" {
  type    = string
  default = "pve-node3"
}

### Cluster
variable "cluster_name" {
  type    = string
  default = "talos"
}

variable "talos_version" {
  type        = string
  default     = "v1.14.5"
  description = "Talos Linux version used for the image factory schematic and installer"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.36.4"
  description = "Pinned below the provider default (1.37.0) to stay on a release line Cilium and the Proxmox CCM have shipped against"
}

variable "gateway" {
  type    = string
  default = "192.168.100.1"
}

variable "subnet_prefix" {
  type        = string
  default     = "192.168.100."
  description = "Prefix used to pick the DHCP address reported by the guest agent during first boot"
}

variable "nameservers" {
  type    = list(string)
  default = ["8.8.8.8", "8.8.4.4"] # same as the k3s VMs; internal names resolve via Cloudflare
}

variable "proxmox_region" {
  type        = string
  default     = "region-1"
  description = "topology.kubernetes.io/region label; must match the region in the proxmox-csi-config secret (k8s-talos/infrastructure/proxmox-csi/secret.yaml)"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "nodes" {
  description = "Cluster nodes keyed by hostname. vm_id doubles as the last IP octet."
  type = map(object({
    role      = string # controlplane | worker
    vm_id     = number
    cpu       = number
    memory    = number # MiB
    disk_size = number # GiB
  }))
  default = {
    "talos-121" = { role = "controlplane", vm_id = 121, cpu = 2, memory = 4096, disk_size = 32 }
    # memory kept small while k3s is still running on the same host (~17 GB free); raise once k3s is decommissioned
    "talos-131" = { role = "worker", vm_id = 131, cpu = 4, memory = 4096, disk_size = 48 }
    "talos-132" = { role = "worker", vm_id = 132, cpu = 4, memory = 4096, disk_size = 48 }
  }
}

### Storage
variable "iso_datastore" {
  type    = string
  default = "local"
}

variable "vm_images_datastore" {
  type    = string
  default = "vmimages"
}

### Cilium
variable "cilium_version" {
  type    = string
  default = "1.20.4"
}

# Must match what the Cilium release supports (https://docs.cilium.io/en/latest/network/servicemesh/gateway-api/gateway-api/)
variable "gateway_api_version" {
  type    = string
  default = "1.6.3"
}

variable "ccm_chart_version" {
  type    = string
  default = "0.2.32"
}

### GitOps
variable "git_url" {
  type    = string
  default = "https://github.com/enrico-laboratory/homelabV2.git"
}

variable "git_branch" {
  type    = string
  default = "main"
}

variable "flux_path" {
  type    = string
  default = "k8s-talos/clusters/talos"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub PAT with contents:write on the repo, used by flux_bootstrap_git"
}

variable "sops_age_key" {
  type        = string
  sensitive   = true
  description = "age private key content so Flux can decrypt SOPS secrets"
}
