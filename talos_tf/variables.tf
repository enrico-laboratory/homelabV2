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
  description = "Talos Linux version used for the image factory schematic and installer. Keep in sync with the TalosUpgrade in k8s-talos/infrastructure-config/tuppr/upgrades.yaml"
}

variable "kubernetes_version" {
  type        = string
  default     = "1.36.4"
  description = "Keep in sync with the KubernetesUpgrade in k8s-talos/infrastructure-config/tuppr/upgrades.yaml. Pinned below the provider default (1.37.0) to stay on a release line Cilium and the Proxmox CCM have shipped against"
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
    gpu       = optional(bool, false) # passes var.gpu through, uses the NVIDIA schematic, taints the node
  }))
  default = {
    "talos-121" = { role = "controlplane", vm_id = 121, cpu = 2, memory = 4096, disk_size = 32 }
    # 7 GB after k3s-112/113 were removed; raise again once k3s is fully decommissioned
    "talos-131" = { role = "worker", vm_id = 131, cpu = 4, memory = 7168, disk_size = 48 }
    "talos-132" = { role = "worker", vm_id = 132, cpu = 4, memory = 7168, disk_size = 48 }
    # replaces k3s-113 (same 6 vCPU / 20 GB); gets the RTX 3060 that win-11 used to have
    "talos-133" = { role = "worker", vm_id = 133, cpu = 6, memory = 20480, disk_size = 64, gpu = true }
  }
}

variable "gpu" {
  description = "PCI passthrough for nodes with gpu = true. rom_file lives in /usr/share/kvm on the Proxmox host"
  type = object({
    id       = string
    rom_file = string
  })
  default = {
    id       = "0000:0c:00.0" # GeForce RTX 3060 (GA106); 0b:00.0 is a GTX 970, not used
    rom_file = "rtx3060.rom"
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
