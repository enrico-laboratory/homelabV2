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
make k3s_config                 # Configure k3s nodes, GPU
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

## Talos cluster (talos_tf/) — migration target

There are two Kubernetes clusters. **Services are being migrated from the k3s cluster to the new Talos cluster**; until the migration is finished both run side by side, and k3s remains the source of truth for anything not yet moved.

| | k3s (legacy) | Talos (new) |
|---|---|---|
| Provisioning | Ansible (`k3s_config`, `k8s_bootstrap_cluster`) | Terraform, `talos_tf/` (1 CP + 2 workers on Proxmox, own state) |
| GitOps | ArgoCD, bootstrapped by Ansible | **Flux**, bootstrapped by Terraform (`flux_bootstrap_git`) |
| Manifests | `k8s/` | `k8s-talos/` (`clusters/talos/` = Flux entrypoint, `infrastructure/` = apps) |
| Secrets | `SopsSecret` CRD (sops-secrets-operator) | Native `Secret` decrypted by Flux |

Run Terraform via `cd talos_tf && make tf-plan|tf-apply` (secrets from `auth.enc.yaml`, see `auth.example.yaml`). The ArgoCD/`k8s/` rules in this file (ArgoCD flow, `SopsSecret`, the `k8s/` layout, the "never use kubectl to create resources" rule) apply to the k3s cluster only. The same "let GitOps manage it" principle applies on Talos: change things by committing to `k8s-talos/`, not with `kubectl`. Use `flux` CLI to inspect and reconcile (`flux get all -A`, `flux reconcile kustomization infrastructure --with-source`). When migrating a service, port its manifests from `k8s/` to `k8s-talos/`, convert its `SopsSecret` to a native `Secret` (see SOPS below), and only remove it from `k8s/` once it is verified on Talos. Notes: `knowledge/flux.md` in the notes repo.

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

**NAS hostname**: `nas.enricoruggieri.com` (a Linux VM on Proxmox, not TrueNAS; only `truenas-backup` is TrueNAS)

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

**k3s cluster (`k8s/`)**: all secrets use the `SopsSecret` CRD (isindir/sops-secrets-operator). Never use plain Kubernetes `Secret` resources in git.

**Talos cluster (`k8s-talos/`)**: the opposite. Flux decrypts SOPS natively, so secrets are plain `v1/Secret` manifests encrypted with SOPS. Do **not** use the `SopsSecret` CRD there (the operator is not installed). See the differences below.

## SOPS + Age Key Management

### Age Key Location
The age private key is stored at: **`~/.sops/age_key.txt`** (user's home directory, not in repo). Both clusters use the same age key.

### k3s vs Talos: SOPS differences

| | k3s (`k8s/`) | Talos (`k8s-talos/`) |
|---|---|---|
| Resource kind | `SopsSecret` (`isindir.github.com/v1alpha3`) | native `Secret` (`v1`) |
| Decrypted by | sops-secrets-operator in the cluster | Flux kustomize-controller (`decryption.provider: sops` on the Flux `Kustomization`) |
| Key in cluster | operator's own age key secret | Secret `sops-age` in `flux-system`, created by Terraform (`talos_tf/flux.tf`) from `sops_age_key` |
| Fields encrypted | `stringData` | `data` and `stringData` |
| Encrypt command | needs explicit `--encrypted-regex '^(stringData)$'` | `.sops.yaml` rule for `k8s-talos/` already sets `encrypted_regex: ^(data\|stringData)$`, so just `sops --encrypt --in-place <file>` |

A new Flux `Kustomization` that contains encrypted files must set `spec.decryption` (`provider: sops`, `secretRef.name: sops-age`), as `k8s-talos/clusters/talos/infrastructure.yaml` does. Without it, the encrypted Secret is applied as-is and the app breaks.

### Encrypting Talos (Flux) secrets

1. Create a plaintext `Secret` at `k8s-talos/infrastructure/{app}/sops_secret.yaml` (use `stringData`, not base64 `data`):
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: {secret-name}
  namespace: {namespace}
stringData:
  key1: plaintext-value-1
```
2. Encrypt and verify:
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --encrypt --in-place k8s-talos/infrastructure/{app}/sops_secret.yaml
sops --decrypt k8s-talos/infrastructure/{app}/sops_secret.yaml
```
3. Add the file to the app's `kustomization.yaml` and commit. Flux decrypts and applies it.

### Encrypting k3s Kubernetes Secrets with SOPS

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

## Host updates

A cron job on `ops` (Sunday 03:00, `ansible/playbooks/cronjob.yaml`) runs `ansible/playbooks/update_hosts.yaml`: apt dist-upgrade plus automatic reboot when needed, in dependency order: k3s agents (serial, drain/uncordon) -> k3s master -> nas -> pve_node3 -> ops (last, detached reboot). `nas_config.yaml` is re-applied after the NAS reboots (and after pve reboots), because the NFS exports are lost on every NAS reboot. A failed run sends a Telegram message (`notify_failure.yaml`). Talos nodes have no apt and are not in the Ansible inventory; they are upgraded by Tuppr (see below).

### Upgrading the Talos cluster (Talos and Kubernetes versions)

Tuppr (`k8s-talos/infrastructure/tuppr`, namespace `system-upgrade`) rolls Talos and Kubernetes one node at a time (cordon, drain, upgrade, reboot, health check). Upgrades are triggered by git, not by cron:

1. Check the target is supported: Talos release notes, and the Kubernetes version must be supported by the target Talos. If both change, upgrade Kubernetes first (Tuppr rejects the Talos upgrade otherwise).
2. Edit the version in `k8s-talos/infrastructure-config/tuppr/upgrades.yaml` (`TalosUpgrade.spec.talos.version` and/or `KubernetesUpgrade.spec.kubernetes.version`, with the `v` prefix).
3. Edit the same value in `talos_tf/variables.tf` (`talos_version`, `kubernetes_version`, no `v` for Kubernetes) so a rebuilt cluster matches. Do **not** run `tf-apply` to upgrade running nodes; Terraform only needs to be applied for new/rebuilt nodes.
4. Commit and push. Flux applies the CR and Tuppr starts. Follow it with `flux reconcile kustomization infrastructure-config --with-source`, `kubectl --kubeconfig ~/.kube/talos-config get talosupgrade,kubernetesupgrade` and `talosctl --talosconfig ~/.talos/config version`.

The installer image and schematic (qemu-guest-agent extension) are taken from each node's current install image, so extensions are preserved. If the schematic itself changes (new extension), change it in `talos_tf/image.tf` and use the `factory-url`/`schematic` annotations described in the Tuppr docs. The Talos API access Tuppr needs (`kubernetesTalosAPIAccess`, namespace `system-upgrade`) is part of the machine config in `talos_tf/talos.tf`; it is enabled on the control plane only (Talos rejects it on workers) and reaches the node only after a `make tf-apply`. On a fresh cluster the Tuppr HelmRelease fails until that feature exists (the chart creates a `talos.dev` ServiceAccount); once the apply is done, `flux reconcile hr tuppr -n system-upgrade --force`. Do not upgrade while the pve host update (Sunday 03:00) is running.

## Infrastructure

- **Proxmox cluster**: nodes at `192.168.100.23` (pve_node3)
- **k3s master**: `k3s-101` at `192.168.100.101`; agents at `.111`, `.112`, `.113`
- **Reverse proxy**: Traefik container on `ops` (`192.168.100.78`) — label discovery for Docker services, TLS passthrough (SNI) to the k8s ingress at `192.168.100.111:443`. kubectl and k3s agents talk to the master `192.168.100.101:6443` directly
- **TrueNAS backup**: `truenas-backup.enricoruggieri.com` — use for NFS backup mounts or rclone targets

## Rules

- **Never use `kubectl` to create resources** — let ArgoCD manage all deployments. Only use kubectl for testing/debugging, never for persistent state changes.
- **SOPS Encryption**: Always use `sops --encrypt --in-place`; never manually encrypt or bypass this workflow. For k3s (`k8s/`) add `--encrypted-regex '^(stringData)$'`; for Talos (`k8s-talos/`) the regex comes from `.sops.yaml`. Details in "SOPS + Age Key Management".
- Every time a new application is added in Kubernetes, update the README.md. Exclude Sonarr, Radarr, and Transmission. Scope by cluster: an app added to k3s (`k8s/`) goes in the "Services Deployed" section; an app added to Talos (`k8s-talos/`) goes in the "Talos Cluster" section. An app migrated from k3s to Talos is moved between those sections once it runs on Talos, not listed in both.
