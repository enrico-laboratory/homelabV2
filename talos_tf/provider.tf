terraform {
  required_version = ">= 1.9"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.108"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.9"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.2"
    }
    flux = {
      source  = "fluxcd/flux"
      version = "~> 1.7"
    }
  }
}

# Credentials come from PROXMOX_VE_USERNAME / PROXMOX_VE_PASSWORD (auth.enc.yaml)
provider "proxmox" {
  endpoint = "https://proxmox3.enricoruggieri.com:8006/"
  insecure = true
  tmp_dir  = "/var/tmp"

  ssh {
    agent = true
  }
}

locals {
  kubeconfig = talos_cluster_kubeconfig.this.kubernetes_client_configuration
}

provider "helm" {
  kubernetes {
    host                   = local.kubeconfig.host
    client_certificate     = base64decode(local.kubeconfig.client_certificate)
    client_key             = base64decode(local.kubeconfig.client_key)
    cluster_ca_certificate = base64decode(local.kubeconfig.ca_certificate)
  }
}

provider "kubernetes" {
  host                   = local.kubeconfig.host
  client_certificate     = base64decode(local.kubeconfig.client_certificate)
  client_key             = base64decode(local.kubeconfig.client_key)
  cluster_ca_certificate = base64decode(local.kubeconfig.ca_certificate)
}

provider "kubectl" {
  host                   = local.kubeconfig.host
  client_certificate     = base64decode(local.kubeconfig.client_certificate)
  client_key             = base64decode(local.kubeconfig.client_key)
  cluster_ca_certificate = base64decode(local.kubeconfig.ca_certificate)
  load_config_file       = false
}

provider "flux" {
  kubernetes = {
    host                   = local.kubeconfig.host
    client_certificate     = base64decode(local.kubeconfig.client_certificate)
    client_key             = base64decode(local.kubeconfig.client_key)
    cluster_ca_certificate = base64decode(local.kubeconfig.ca_certificate)
  }
  git = {
    url    = var.git_url
    branch = var.git_branch
    http = {
      username = "git"
      password = var.github_token
    }
  }
}
