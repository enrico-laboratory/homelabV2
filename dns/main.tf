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