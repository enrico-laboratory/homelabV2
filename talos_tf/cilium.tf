# Cilium is installed here because the nodes cannot become Ready (and Flux cannot run) without a CNI.
# LB-IPAM pool and L2 announcement policy live in k8s-talos/ (Flux), since their CRDs come from this chart.
resource "helm_release" "cilium" {
  depends_on = [data.talos_cluster_health.control_plane]

  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  wait       = true

  values = [yamlencode({
    ipam                 = { mode = "kubernetes" }
    kubeProxyReplacement = true
    k8sServiceHost       = local.controlplane_ip
    k8sServicePort       = 6443

    l2announcements    = { enabled = true }
    externalIPs        = { enabled = true }
    k8sClientRateLimit = { qps = 50, burst = 100 } # required by l2announcements

    # Talos specifics: https://www.talos.dev/latest/kubernetes-guides/network/deploying-cilium/
    securityContext = {
      capabilities = {
        ciliumAgent      = ["CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER", "SETGID", "SETUID"]
        cleanCiliumState = ["NET_ADMIN", "SYS_ADMIN", "SYS_RESOURCE"]
      }
    }
    cgroup = {
      autoMount = { enabled = false }
      hostRoot  = "/sys/fs/cgroup"
    }
  })]
}
