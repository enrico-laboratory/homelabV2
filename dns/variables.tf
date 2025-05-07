variable "private_ip" {
  type = list(object({
    name    = string
    content = string
  }))
}

variable "private_cname" {
  type = list(object({
    name    = string
    content = string
  }))
}

variable "cloudflare_api_token" {
  description = "API token with DNS edit access"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID"
  type        = string
}