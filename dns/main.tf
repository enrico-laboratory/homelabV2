# Cloudflare Access: block all external access to Nextcloud except anonymous share links
# Local users hit PiHole → 192.168.100.140 directly and never touch Cloudflare Access.

resource "cloudflare_zero_trust_access_application" "nextcloud_shares" {
  account_id = var.cloudflare_account_id
  name       = "Nextcloud Share Links"
  domain     = "nextcloud.enricoruggieri.com/s/"
  type       = "self_hosted"
}

resource "cloudflare_zero_trust_access_policy" "nextcloud_shares_bypass" {
  application_id = cloudflare_zero_trust_access_application.nextcloud_shares.id
  account_id     = var.cloudflare_account_id
  name           = "Bypass anonymous share links"
  precedence     = 1
  decision       = "bypass"

  include {
    everyone = true
  }
}

resource "cloudflare_zero_trust_access_application" "nextcloud_shares_legacy" {
  account_id = var.cloudflare_account_id
  name       = "Nextcloud Share Links (legacy path)"
  domain     = "nextcloud.enricoruggieri.com/index.php/s/"
  type       = "self_hosted"
}

resource "cloudflare_zero_trust_access_policy" "nextcloud_shares_legacy_bypass" {
  application_id = cloudflare_zero_trust_access_application.nextcloud_shares_legacy.id
  account_id     = var.cloudflare_account_id
  name           = "Bypass anonymous share links (legacy)"
  precedence     = 1
  decision       = "bypass"

  include {
    everyone = true
  }
}

resource "cloudflare_zero_trust_access_application" "nextcloud" {
  account_id       = var.cloudflare_account_id
  name             = "Nextcloud"
  domain           = "nextcloud.enricoruggieri.com"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_policy" "nextcloud_deny" {
  application_id = cloudflare_zero_trust_access_application.nextcloud.id
  account_id     = var.cloudflare_account_id
  name           = "Deny all external access"
  precedence     = 1
  decision       = "deny"

  include {
    everyone = true
  }
}

resource "cloudflare_record" "internal_ip" {
  for_each = {
    for record in var.private_ip : record.name => record
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  content = each.value.content
  type    = "A"
  ttl     = 3600
  proxied = false
}

resource "cloudflare_record" "internal_cname" {
  for_each = {
    for record in var.private_cname : record.name => record
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  content = each.value.content
  type    = "CNAME"
  ttl     = 3600
  proxied = false
}