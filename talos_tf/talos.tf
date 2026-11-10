locals {
  controlplane_name = one([for k, v in var.nodes : k if v.role == "controlplane"])
  controlplane_ip   = "${var.subnet_prefix}${var.nodes[local.controlplane_name].vm_id}"
  cluster_endpoint  = "https://${local.controlplane_ip}:6443"

  static_ips = { for k, v in var.nodes : k => "${var.subnet_prefix}${v.vm_id}" }

  # first boot is DHCP (maintenance mode); the guest agent reports it. After install the
  # node answers on its static IP, which also starts with the same prefix.
  apply_ips = {
    for k, vm in proxmox_virtual_environment_vm.talos : k =>
    [for ip in flatten(vm.ipv4_addresses) : ip if startswith(ip, var.subnet_prefix)][0]
  }
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "this" {
  for_each = var.nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = each.value.role
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = each.key
          interfaces = [{
            deviceSelector = { driver = "virtio_net" }
            addresses      = ["${local.static_ips[each.key]}/24"]
            routes         = [{ network = "0.0.0.0/0", gateway = var.gateway }]
          }]
          nameservers = var.nameservers
        }
        install = {
          disk  = "/dev/sda"
          image = data.talos_image_factory_urls.this.urls.installer
        }
        # proxmox-csi-plugin matches nodes to VMs by these labels
        nodeLabels = {
          "topology.kubernetes.io/region" = var.proxmox_region
          "topology.kubernetes.io/zone"   = var.node_name
        }
      }
      cluster = {
        network = { cni = { name = "none" } }
        proxy   = { disabled = true }
        # kubelet runs with --cloud-provider=external: nodes stay tainted
        # (node.cloudprovider.kubernetes.io/uninitialized) until the Proxmox CCM initializes them
        externalCloudProvider = { enabled = true }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "this" {
  for_each = var.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  node                        = local.apply_ips[each.key]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.controlplane_ip
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.controlplane_ip]
  nodes                = values(local.static_ips)
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.controlplane_ip
}

# Kubernetes-level checks are skipped: nodes stay NotReady until Cilium is installed
data "talos_cluster_health" "control_plane" {
  depends_on = [talos_cluster_kubeconfig.this]

  client_configuration   = data.talos_client_configuration.this.client_configuration
  control_plane_nodes    = [local.controlplane_ip]
  worker_nodes           = [for k, v in var.nodes : local.static_ips[k] if v.role == "worker"]
  endpoints              = data.talos_client_configuration.this.endpoints
  skip_kubernetes_checks = true
}
