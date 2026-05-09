# homelabV2

A complete Infrastructure-as-Code homelab setup for self-hosted Kubernetes on Proxmox, managed through GitOps with ArgoCD.

## Overview

This repository contains the complete automation stack for a production-like homelab environment featuring:

- **Kubernetes on Proxmox**: k3s clusters deployed on Proxmox VE virtualization platform
- **GitOps with ArgoCD**: Declarative application management and auto-syncing from git
- **Unified Secret Management**: SOPS+age encryption for all secrets across Kubernetes, Ansible, and Terraform
- **Infrastructure as Code**: Terraform configurations for Proxmox resource management
- **Automated Provisioning**: Ansible playbooks for cluster bootstrapping and service deployment

## Repository Structure

```
homelabV2/
├── k8s/                           # Kubernetes manifests and ArgoCD applications
│   ├── argocd-apps/              # Application definitions (auto-synced by ArgoCD)
│   │   ├── tooling/              # Core services (SOPS, cert-manager, monitoring)
│   │   ├── mediaserver/          # Media and content services
│   │   └── ai/                   # AI/ML services
│   └── argocd-projects/          # ArgoCD project definitions
├── ansible/                       # Ansible automation
│   ├── playbooks/                # Cluster bootstrap and configuration
│   ├── roles/                    # Reusable task collections
│   └── inventories/              # Host inventory and encrypted variables
├── pve_tf/                        # Terraform for Proxmox infrastructure
├── .sops.yaml                     # SOPS encryption configuration
└── CLAUDE.md                      # Development guidelines
```

## Key Features

### Secrets Management
- **SOPS + age encryption**: All sensitive data encrypted at rest
- **Selective encryption**: Only secret values encrypted, maintaining readability of YAML structure
- **Unified approach**: Single tool (SOPS) across Kubernetes, Ansible, and Terraform

### GitOps Workflow
- ArgoCD watches this repository for changes
- Automatic sync of applications and configurations
- App-of-apps pattern for scalable application management
- Helm chart integration for package deployment

### Infrastructure
- **Proxmox VE**: Virtualization platform for VM management
- **k3s**: Lightweight Kubernetes distribution
- **Container Registry**: Private image storage
- **Ingress**: Nginx with automatic TLS via cert-manager

## Services Deployed

### Core Infrastructure
- ArgoCD (GitOps controller)
- Cert-Manager (TLS automation)
- Prometheus + Grafana (monitoring)
- Proxmox CSI (storage integration)
- MetalLB (load balancer)

### Media & Applications
- Jellyfin (media streaming)
- Nextcloud (cloud storage)
- Navidrome (music streaming)
- Joplin (notes)

### AI & ML Services
- Ollama (LLM inference)
- Qdrant (vector database)
- Open WebUI (AI model management interface)

## Quick Start

### Prerequisites
- Proxmox VE cluster with SSH access
- Ansible, kubectl installed
- Age encryption key: `~/.sops/age_key.txt`

### Bootstrap Cluster

```bash
# Generate encryption key (if needed)
age-keygen -o ~/.sops/age_key.txt

# Deploy Kubernetes
cd ansible
ansible-playbook playbooks/pve_1_bootstrap_node3.yaml
ansible-playbook playbooks/k8s_bootstrap_cluster.yaml

# Verify ArgoCD
kubectl get applications -n argocd
```

## License

Personal homelab setup. Adapt as needed for your environment.
