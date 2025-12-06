terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.87.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://proxmox3.enricoruggieri.com:8006/"
  insecure = true
  tmp_dir  = "/var/tmp"

  ssh {
    agent = true
  }
}