resource "flux_bootstrap_git" "this" {
  # nodes must be initialized by the CCM, otherwise Flux pods cannot schedule
  depends_on = [helm_release.proxmox_ccm]

  path                 = var.flux_path
  embedded_manifests   = true
  namespace            = "flux-system"
  interval             = "5m"
  components_extra     = []
  keep_namespace       = true
  delete_git_manifests = false
}

# Flux decrypts SOPS secrets (Kustomization.spec.decryption.secretRef = sops-age)
resource "kubernetes_secret" "sops_age" {
  depends_on = [flux_bootstrap_git.this]

  metadata {
    name      = "sops-age"
    namespace = "flux-system"
  }

  data = {
    "age.agekey" = var.sops_age_key
  }
}
