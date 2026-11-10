# Proxmox cloud controller manager. Installed here, not by Flux: with externalCloudProvider enabled the
# nodes are tainted "uninitialized" until the CCM runs, and Flux's own pods could not schedule.
#
# The Proxmox API config is read from the same SOPS file Flux applies for the CSI plugin,
# so the token lives in one place in git.
data "sops_file" "proxmox_config" {
  source_file = "${path.module}/../k8s-talos/infrastructure/proxmox-csi/sops_secret.yaml"
}

resource "kubernetes_secret" "proxmox_ccm_config" {
  depends_on = [talos_cluster_kubeconfig.this]

  metadata {
    name      = "proxmox-ccm-config"
    namespace = "kube-system"
  }

  data = {
    "config.yaml" = yamldecode(data.sops_file.proxmox_config.raw).stringData["config.yaml"]
  }
}

resource "helm_release" "proxmox_ccm" {
  depends_on = [helm_release.cilium, kubernetes_secret.proxmox_ccm_config]

  name       = "proxmox-ccm"
  namespace  = "kube-system"
  repository = "oci://ghcr.io/sergelogvinov/charts"
  chart      = "proxmox-cloud-controller-manager"
  version    = var.ccm_chart_version
  wait       = true

  values = [yamlencode({
    existingConfigSecret    = kubernetes_secret.proxmox_ccm_config.metadata[0].name
    existingConfigSecretKey = "config.yaml"
    # DaemonSet mode uses hostNetwork, so it does not depend on the pod network being ready
    useDaemonSet = true
    nodeSelector = { "node-role.kubernetes.io/control-plane" = "" }
  })]
}
