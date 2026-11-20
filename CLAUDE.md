# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Infrastructure-as-code repository for managing a self-hosted Kubernetes/virtualization homelab with Proxmox, networking, and monitoring infrastructure.

## Running Ansible Playbooks

All playbooks are run from `ansible/` using the Makefile:

```bash
cd ansible
make <target>
# e.g.:
make compose_apps               # Deploy docker-compose apps on ops (Traefik, monitoring, pihole, etc.)
make dns_config                 # Configure DNS records via Ansible
make nas_config                 # NAS datasets, NFS exports, SMB shares, sanoid
make update_hosts               # apt upgrade + reboot of nas, pve and ops (see Host updates)
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

# Proxmox VMs other than the Talos nodes (nas, win-11) and the CSI user/token
cd pve_tf
terraform plan && terraform apply
```

Terraform variables are stored encrypted as `terraform.tfvars.enc` / `auth.enc.yaml` (SOPS-encrypted). Decrypt before use:
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --decrypt dns/terraform.tfvars.enc > /tmp/terraform.tfvars   # never commit decrypted
```

## Kubernetes: the Talos cluster (talos_tf/, k8s-talos/)

The homelab runs one Kubernetes cluster, Talos Linux on Proxmox (control plane `talos-121`, workers `talos-131/132`, GPU worker `talos-133`). It replaced the former k3s/ArgoCD cluster in November 2026 (migration log: `logs/2026-11-19-k3s-to-talos-migration-plan.md` in the notes repo).

- **Provisioning**: Terraform, `talos_tf/` (VMs, machine config, bootstrap, Cilium, Flux; own state). Run it via `cd talos_tf && make tf-plan|tf-apply` (secrets from `auth.enc.yaml`, see `auth.example.yaml`). `make configs` writes `~/.talos/config` and `~/.kube/talos-config`.
- **GitOps**: Flux, bootstrapped by Terraform (`flux_bootstrap_git`). Change things by committing to `k8s-talos/`, never with `kubectl`. Use the `flux` CLI to inspect and reconcile (`flux get all -A`, `flux reconcile kustomization infrastructure --with-source`). Notes: `knowledge/flux.md` in the notes repo.
- **kubectl**: always `--kubeconfig ~/.kube/talos-config` (or `KUBECONFIG=~/.kube/talos-config`); `~/.kube/config` is the old k3s cluster, which no longer exists.

### Manifest layout

```
k8s-talos/
├── clusters/talos/          # Flux entrypoint: one Kustomization per layer and per app group
│   ├── infrastructure.yaml  # -> infrastructure/
│   ├── infrastructure-config.yaml
│   └── apps-<group>.yaml    # -> apps/<group>/ (mediaserver, cloud, ai, cloudflare)
├── infrastructure/          # Platform (Cilium config, gateway, cert-manager, Proxmox CSI, monitoring, Tuppr, NVIDIA…)
├── infrastructure-config/   # Resources that need the platform CRDs (ClusterIssuer, Tuppr upgrade CRs…)
└── apps/<group>/<app>/      # One folder per app, each with its own kustomization.yaml
```

Each group owns its `namespace.yaml` and lists its apps in `apps/<group>/kustomization.yaml`; each app `kustomization.yaml` sets `namespace:`. Helm apps use a `HelmRepository` + `HelmRelease` pair (see `k8s-talos/apps/cloud/nextcloud/helmrelease.yaml`). Services are ClusterIP; nothing uses `type: LoadBalancer` except the Gateway and Prometheus.

### HTTPRoute pattern

There are no `Ingress` resources. Every app gets an `httproute.yaml` attached to the shared Gateway; TLS is terminated there with the wildcard certificate, so no per-app certificate or cert-manager annotation is needed:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <namespace>
spec:
  parentRefs:
  - name: main
    namespace: gateway
    sectionName: https
  hostnames:
  - <app>.enricoruggieri.com
  rules:
  - backendRefs:
    - name: <service>
      port: <port>
```

Long requests (uploads, websockets with long idle) need `rules[].timeouts.request` (Nextcloud and OnlyOffice use `3600s`). A new hostname must also be added to `talos_hostnames` in `ansible/playbooks/compose_apps.yaml`, then `make compose_apps`, so Traefik passes it through.

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
  - `ollama-models/`: LLM model cache
  - Other app-specific datasets
- `tank-fast/`: Faster NVMe pool for latency-sensitive workloads
- `fast-pool1/`: Legacy fast storage (being phased out)

**Block storage in Kubernetes**: Proxmox CSI on the `kubedata` ZFS pool (`kube-pool`), StorageClasses `proxmox-zfs-nvme` (default) and `proxmox-zfs-kubedata-ext4`; WaitForFirstConsumer, volume expansion allowed.

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
- `rw=@192.168.100.0/24`: Read-write to the homelab subnet
- `no_root_squash`: Allow containers running as root to write (required for many k8s apps)
- `nohide, no_subtree_check`: Standard k8s-friendly options

**To add a new NFS dataset:**
1. Add entry to `zfs_datasets` in `nas_config.yaml` with `nfs: enabled: true`
2. Specify NFS options (use `ollama-models` or `comfyui-output` as templates)
3. Run `make nas_config`
4. Update the k8s deployment to mount the new dataset

### Networking

- **Cilium**: CNI with kube-proxy replacement and L2 LB-IPAM (pool `192.168.100.200-219`)
- **Gateway API**: Cilium native Gateway `gateway/main` on `192.168.100.202`, reached only through Traefik on `ops` (TLS passthrough by SNI + PROXY protocol v2); direct connections are rejected. Pod CIDR `10.244.0.0/16` (what apps see as the proxy address, e.g. Nextcloud `trusted_proxies`)
- **cert-manager**: Let's Encrypt wildcard certificate for `*.enricoruggieri.com` via DNS01 (Cloudflare). ClusterIssuer: `letsencrypt-cloudflare`
- **Cloudflared**: Cloudflare tunnel (`apps/cloudflare/cloudflared`) for external access; its only public hostname is `nextcloud.enricoruggieri.com` -> `http://nextcloud.cloud.svc.cluster.local:8080`, configured in the Cloudflare dashboard (not Terraform)
- **DNS**: `enricoruggieri.com` managed via Cloudflare; internal records in Terraform (`dns/`); Pi-hole for local resolution

### Secret Management

Flux decrypts SOPS natively, so secrets are plain `v1/Secret` manifests encrypted with SOPS (`sops_secret.yaml` in the app folder). There is no `SopsSecret` CRD (sops-secrets-operator is not installed).

## SOPS + Age Key Management

### Age Key Location
The age private key is stored at: **`~/.sops/age_key.txt`** (user's home directory, not in repo).

### How Flux decrypts

- Flux kustomize-controller decrypts with `decryption.provider: sops` on the Flux `Kustomization`, using the Secret `sops-age` in `flux-system` (created by Terraform, `talos_tf/flux.tf`, from `sops_age_key`).
- A new Flux `Kustomization` that contains encrypted files must set `spec.decryption` (`provider: sops`, `secretRef.name: sops-age`), as `k8s-talos/clusters/talos/infrastructure.yaml` does. Without it, the encrypted Secret is applied as-is and the app breaks.
- The `.sops.yaml` rule for `k8s-talos/` sets `encrypted_regex: ^(data|stringData)$`, so only the values are encrypted.

### Encrypting secrets

1. Create a plaintext `Secret` at `k8s-talos/apps/<group>/<app>/sops_secret.yaml` (or `k8s-talos/infrastructure/<app>/`), using `stringData`, not base64 `data`:
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
sops --encrypt --in-place k8s-talos/apps/<group>/<app>/sops_secret.yaml
sops --decrypt k8s-talos/apps/<group>/<app>/sops_secret.yaml
```
3. Add the file to the app's `kustomization.yaml` and commit. Flux decrypts and applies it.

## Host updates

A cron job on `ops` (Sunday 03:00, `ansible/playbooks/cronjob.yaml`) runs `ansible/playbooks/update_hosts.yaml`: apt dist-upgrade plus automatic reboot when needed, in dependency order: nas -> pve_node3 -> ops (last, detached reboot). `nas_config.yaml` is re-applied after the NAS reboots (and after pve reboots), because the NFS exports are lost on every NAS reboot. A failed run sends a Telegram message (`notify_failure.yaml`). Talos nodes have no apt and are not in the Ansible inventory; they are upgraded by Tuppr (see below).

### Upgrading the Talos cluster (Talos and Kubernetes versions)

Tuppr (`k8s-talos/infrastructure/tuppr`, namespace `system-upgrade`) rolls Talos and Kubernetes one node at a time (cordon, drain, upgrade, reboot, health check). Upgrades are triggered by git, not by cron:

1. Check the target is supported: Talos release notes, and the Kubernetes version must be supported by the target Talos. If both change, upgrade Kubernetes first (Tuppr rejects the Talos upgrade otherwise).
2. Edit the version in `k8s-talos/infrastructure-config/tuppr/upgrades.yaml` (`TalosUpgrade.spec.talos.version` and/or `KubernetesUpgrade.spec.kubernetes.version`, with the `v` prefix).
3. Edit the same value in `talos_tf/variables.tf` (`talos_version`, `kubernetes_version`, no `v` for Kubernetes) so a rebuilt cluster matches. Do **not** run `tf-apply` to upgrade running nodes; Terraform only needs to be applied for new/rebuilt nodes.
4. Commit and push. Flux applies the CR and Tuppr starts. Follow it with `flux reconcile kustomization infrastructure-config --with-source`, `kubectl --kubeconfig ~/.kube/talos-config get talosupgrade,kubernetesupgrade` and `talosctl --talosconfig ~/.talos/config version`.

The installer image and schematic (qemu-guest-agent extension) are taken from each node's current install image, so extensions are preserved. If the schematic itself changes (new extension), change it in `talos_tf/image.tf` and use the `factory-url`/`schematic` annotations described in the Tuppr docs. The GPU node has its own schematic (NVIDIA LTS driver + container toolkit, `talos_image_factory_schematic.gpu`); a schematic change on a running node needs `talosctl upgrade --image <new installer>`, a config apply alone does not reinstall extensions. The Talos API access Tuppr needs (`kubernetesTalosAPIAccess`, namespace `system-upgrade`) is part of the machine config in `talos_tf/talos.tf`; it is enabled on the control plane only (Talos rejects it on workers) and reaches the node only after a `make tf-apply`. On a fresh cluster the Tuppr HelmRelease fails until that feature exists (the chart creates a `talos.dev` ServiceAccount); once the apply is done, `flux reconcile hr tuppr -n system-upgrade --force`. Do not upgrade while the pve host update (Sunday 03:00) is running.

Changing a node's CPU or memory (`nodes` in `talos_tf/variables.tf`) reboots the VM: drain it first, apply with `-target` one node at a time, then uncordon.

## Infrastructure

- **Proxmox**: single node `pve_node3` at `192.168.100.23`
- **Talos**: control plane `talos-121`, workers `talos-131`, `talos-132`, GPU worker `talos-133` (`192.168.100.133`, RTX 3060 `0000:0c:00.0` passed through; the GTX 970 at `0000:0b:00.0` is unused)
- **Reverse proxy**: Traefik container on `ops` (`192.168.100.78`) — label discovery for Docker services, TLS passthrough (SNI) to the Talos Gateway at `192.168.100.202:443`
- **TrueNAS backup**: `truenas-backup.enricoruggieri.com` — use for NFS backup mounts or rclone targets (restic repos for nextcloud, karakeep, arr-postgres)

## Rules

- **Never use `kubectl` to create resources** — let Flux manage everything from `k8s-talos/`. Only use kubectl for testing/debugging, never for persistent state changes.
- **SOPS Encryption**: Always use `sops --encrypt --in-place`; never manually encrypt or bypass this workflow. The regex comes from `.sops.yaml`. Details in "SOPS + Age Key Management".
- Every time a new application is added in Kubernetes, update the "Talos Cluster" section of README.md.
