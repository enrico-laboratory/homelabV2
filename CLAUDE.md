# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Infrastructure-as-code repository for managing a self-hosted Kubernetes/virtualization homelab with Proxmox, networking, and monitoring infrastructure.

## Running Ansible Playbooks

All playbooks are run from `ansible/` using the Makefile:

```bash
cd ansible
make <target>
# e.g.:
make k8s_bootstrap_cluster     # Deploy ArgoCD and bootstrap the cluster
make k3s_config                 # Configure k3s nodes, proxy, GPU
make compose_apps               # Deploy docker-compose apps (monitoring, pihole, etc.)
make dns_config                 # Configure DNS records via Ansible
make update_hosts               # Update /etc/hosts on nodes
make ops                        # Ops-level tasks
```

To run any arbitrary playbook:
```bash
cd ansible
make run play=<playbook_name_without_extension>
```

The Makefile automatically sets `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`.

## Terraform (DNS & Proxmox)

```bash
# DNS records (Cloudflare)
cd dns
terraform plan && terraform apply

# Proxmox infrastructure
cd pve_tf
terraform plan && terraform apply
```

Terraform variables are stored encrypted as `terraform.tfvars.enc` / `auth.enc.yaml` (SOPS-encrypted). Decrypt before use:
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --decrypt dns/terraform.tfvars.enc > /tmp/terraform.tfvars   # never commit decrypted
```

## Architecture

### GitOps Flow

ArgoCD is **bootstrapped via Ansible** (not managed by itself initially). Once running, it self-manages all cluster resources from this git repo:

1. **Ansible bootstrap** (`k8s_bootstrap_cluster.yaml`) deploys ArgoCD via Helm, then creates two seed Applications:
   - `argocd-apps` — watches `k8s/argocd-apps/` (recursive), instantiates all Application CRs
   - `argocd-app-projects` — watches `k8s/argocd-projects/`, instantiates AppProject CRs
2. From then on, pushing to `main` triggers ArgoCD auto-sync

### Kubernetes Manifest Layout

```
k8s/
├── argocd-apps/            # Application CRs (one per service, grouped by project)
│   ├── tooling/            # Core infra apps (cert-manager, sops-operator, prometheus…)
│   ├── mediaserver/        # Media apps (jellyfin, navidrome, joplin…)
│   ├── ai/                 # AI apps (ollama, qdrant, webui)
│   └── cloud/              # Cloud apps (nextcloud, onlyoffice)
├── argocd-projects/        # AppProject CRs (namespace + RBAC boundaries)
├── tooling/                # Manifests for core infra (cert-manager, metallb, CSI…)
├── mediaserver/            # Manifests for media services
├── cloud/                  # Manifests for cloud services
└── cloudflare/             # Cloudflare tunnel configs
```

Each service under `mediaserver/`, `cloud/`, etc. typically contains: `deployment.yaml`, `service.yaml`, `ingress.yaml`, `sops_secret.yaml`, and a PVC if needed.

### ArgoCD Helm Configuration

ArgoCD is deployed via Helm chart (`argocd/argo-cd`). The overriding values are in:
`ansible/playbooks/roles/k8s_argocd_deploy/files/values_overwrite.yaml`

To apply changes to ArgoCD's own config, edit that file and re-run:
```bash
cd ansible && make k8s_bootstrap_cluster
```

### NAS & Storage Management

**NAS hostname**: `nas.enricoruggieri.com` (TrueNAS)

**All NAS datasets, NFS exports, and SMB shares are managed via Ansible** in `ansible/playbooks/nas_config.yaml`. This playbook:
- Manages ZFS datasets and pools
- Configures NFS exports with proper permissions and options
- Manages SMB shares for Windows clients
- Handles backups via Sanoid/Syncoid

**When modifying NAS configuration:**
1. Edit `ansible/playbooks/nas_config.yaml` to define datasets, pools, and export options
2. Run: `cd ansible && make nas_config`
3. Changes are idempotent — re-running applies only missing or changed items

**NAS Storage Layout:**
- `tank-data/`: Primary storage pool for media, app configs, and large datasets
  - `media/`: Movies, music, audiobooks, TV shows
  - `comfyui/`: ComfyUI outputs, inputs, and user data
  - `ollama-models/`: LLM model cache (NFS-mounted by k8s)
  - Other app-specific datasets
- `tank-fast/`: Faster NVMe pool for latency-sensitive workloads
- `fast-pool1/`: Legacy fast storage (being phased out)

**NFS Mount Pattern in Kubernetes:**
NFS volumes are mounted directly as inline volumes in Deployment specs (no PV/PVC abstraction):
```yaml
volumes:
  - name: app-data
    nfs:
      server: nas.enricoruggieri.com
      path: /tank-data/app-name/subfolder
      readOnly: false  # omit if false
```

All NFS datasets are exported with:
- `rw=@192.168.100.0/24`: Read-write to k8s subnet
- `no_root_squash`: Allow containers running as root to write (required for many k8s apps)
- `nohide, no_subtree_check`: Standard k8s-friendly options

**To add a new NFS dataset:**
1. Add entry to `zfs_datasets` in `nas_config.yaml` with `nfs: enabled: true`
2. Specify NFS options (use `ollama-models` or `comfyui-output` as templates)
3. Run `make nas_config`
4. Update k8s deployment to mount the new dataset

### Networking

- **MetalLB**: Provides LoadBalancer IPs for services on the `192.168.100.x` subnet
- **ingress-nginx**: Single ingress controller deployed in `ingress-nginx` namespace, handles TLS termination for all services
- **cert-manager**: Issues Let's Encrypt certificates via DNS01 challenge (Cloudflare). ClusterIssuer: `letsencrypt-cloudflare`
- **Cloudflared**: Cloudflare tunnel for external access to selected services
- **DNS**: `enricoruggieri.com` managed via Cloudflare; internal records in Terraform (`dns/`); Pi-hole for local resolution

### Ingress Pattern

All service ingresses follow this pattern (TLS via cert-manager DNS01):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service>
  namespace: <namespace>
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-cloudflare
spec:
  ingressClassName: nginx
  rules:
    - host: "<service>.enricoruggieri.com"
      http:
        paths:
          - pathType: Prefix
            path: "/"
            backend:
              service:
                name: <service>-service
                port:
                  number: <port>
  tls:
    - hosts:
        - <service>.enricoruggieri.com
      secretName: <service>-cert-tls
```

### Secret Management

All secrets use `SopsSecret` CRD (isindir/sops-secrets-operator). Never use plain Kubernetes `Secret` resources in git.

## SOPS + Age Key Management

### Age Key Location
The age private key is stored at: **`~/.sops/age_key.txt`** (user's home directory, not in repo)

### Encrypting Kubernetes Secrets with SOPS

**Always use selective encryption** with the `--encrypted-regex` flag to encrypt only `stringData` fields.

#### Step-by-step for new secrets:

1. **Create plaintext SopsSecret** at `k8s/{namespace}/{app}/sops_secret.yaml`:
```yaml
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
    name: {app}-secrets-sops
    namespace: {namespace}
spec:
    secretTemplates:
        - name: {secret-name}
          stringData:
            key1: plaintext-value-1
```

2. **Encrypt**:
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --encrypt --in-place --encrypted-regex '^(stringData)$' k8s/{namespace}/{app}/sops_secret.yaml
```

3. **Verify**:
```bash
sops --decrypt k8s/{namespace}/{app}/sops_secret.yaml
```

## Infrastructure

- **Proxmox cluster**: nodes at `192.168.100.23` (pve_node3)
- **k3s master**: `k3s-101` at `192.168.100.101`; agents at `.111`, `.112`, `.113`
- **Proxy/LB**: `192.168.100.140`
- **TrueNAS backup**: `truenas-backup.enricoruggieri.com` — use for NFS backup mounts or rclone targets

## Rules

- **Never use `kubectl` to create resources** — let ArgoCD manage all deployments. Only use kubectl for testing/debugging, never for persistent state changes.
- **SOPS Encryption**: Always use `--encrypt --in-place --encrypted-regex '^(stringData)$'`. Never manually encrypt or bypass this workflow.
- Every time a new application is added in Kubernetes, update the README.md. Exclude Sonarr, Radarr, and Transmission.
