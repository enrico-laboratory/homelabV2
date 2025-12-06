resource "proxmox_virtual_environment_acme_account" "default" {
  name      = "default"
  contact   = var.acme_email
  directory = "https://acme-v02.api.letsencrypt.org/directory"
  tos       = "https://letsencrypt.org/documents/LE-SA-v1.5-February-24-2025.pdf"
}

resource "proxmox_virtual_environment_acme_dns_plugin" "cloudflare" {
  plugin = "cloudflare"
  api    = "cf"
  data = {
    CF_Account_ID = var.cf_account_id
    CF_Token      = var.cf_token
    CF_Zone_ID    = var.cf_zone_id
  }
}

## Ordering a certificate must be done from the ui

