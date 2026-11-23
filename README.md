# homelabV2

Infrastructure-as-Code homelab: a Talos Linux Kubernetes cluster on Proxmox, managed through GitOps with Flux.

## Overview

- **Kubernetes on Proxmox**: Talos Linux cluster, fully provisioned by Terraform (`talos_tf/`)
- **GitOps with Flux**: Flux is bootstrapped by Terraform and reconciles `k8s-talos/` from this repository
- **Unified secret management**: SOPS + age for every secret across Kubernetes, Ansible and Terraform
- **Infrastructure as Code**: Terraform for Proxmox VMs (`pve_tf/`), the cluster (`talos_tf/`) and DNS (`dns/`)
- **Host automation**: Ansible for the Proxmox node, the NAS, the `ops` Docker host (Traefik and the other compose apps) and the weekly host updates

## Repository Structure

```
homelabV2/
├── k8s-talos/                     # Flux GitOps tree
│   ├── clusters/talos/           # Flux entrypoint (one Kustomization per layer and app group)
│   ├── infrastructure/           # Platform: Cilium config, gateway, cert-manager, CSI, monitoring, Tuppr, NVIDIA…
│   ├── infrastructure-config/    # Resources that need the platform CRDs (issuers, upgrade CRs…)
│   └── apps/<group>/<app>/       # Apps: mediaserver, cloud, ai, cloudflare
├── talos_tf/                      # Terraform for the Talos cluster (VMs, machine config, Cilium, Flux)
├── pve_tf/                        # Terraform for the other Proxmox VMs (NAS, win-11) and the CSI user
├── dns/                           # Terraform for the Cloudflare DNS records
├── ansible/                       # Playbooks for pve, NAS, ops and host updates
├── .sops.yaml                     # SOPS encryption rules
└── CLAUDE.md                      # Development guidelines
```

## Talos Cluster

A Talos Linux cluster on Proxmox (1 control plane `talos-121`, 2 workers `talos-131/132`, GPU worker `talos-133`), fully provisioned by `talos_tf/`:

- VMs, machine config, bootstrap and kubeconfig via the `bpg/proxmox` and `siderolabs/talos` providers
- Cilium as CNI (kube-proxy replacement, L2 LB-IPAM pool 192.168.100.200-219)
- Flux bootstrapped from Terraform, reconciling `k8s-talos/clusters/talos`
- Storage: Proxmox CSI on the `kubedata` ZFS pool; NFS via inline volumes to the NAS
- Ingress: Cilium native Gateway API (GatewayClass `cilium`, shared Gateway `gateway/main` on `192.168.100.202`); Gateway API CRDs are installed by Terraform before Cilium. Reached only through Traefik on `ops` (TLS passthrough by SNI + PROXY protocol v2, so the client source IP is preserved); direct connections to the Gateway IP are rejected
- External access: Cloudflare Tunnel (`cloudflared` in `cloudflare`) for `nextcloud.enricoruggieri.com` only
- cert-manager (Gateway API support) with the `letsencrypt-cloudflare` ClusterIssuer (DNS01) issuing a wildcard certificate for `*.enricoruggieri.com`
- Hubble UI (flow visibility) on `https://hubble.enricoruggieri.com` via HTTPRoute, LAN only, no authentication
- Headlamp (cluster dashboard with the Flux plugin) on `https://headlamp.enricoruggieri.com` via HTTPRoute, LAN only, login with the `headlamp-admin` ServiceAccount token
- Upgrades: Tuppr (`system-upgrade`) rolls Talos and Kubernetes one node at a time; bump the versions in `k8s-talos/infrastructure-config/tuppr/upgrades.yaml` (and `talos_tf/variables.tf`)
- Monitoring: kube-prometheus-stack (Prometheus + Alertmanager with Telegram, Cilium/Hubble metrics) in `monitoring`; no in-cluster Grafana, Prometheus is exposed on `192.168.100.200:9090` and visualised from the Grafana on `ops`
- Apps (`k8s-talos/apps/<group>/`, one Flux Kustomization per group; migrated from the former k3s cluster in November 2026):
  - mediaserver: Jellyfin (media streaming), Navidrome (music streaming), Joplin (notes, with its Postgres), Karakeep (bookmarks and notes, with nightly restic backup to TrueNAS), Meal Plan (personal dashboard at personal.enricoruggieri.com), Calibre-Web (ebook library), Jackett and Prowlarr (indexers), Sonarr (TV shows) and Radarr (movies), Transmission (torrent client), arr-postgres (one shared Postgres for Sonarr, Radarr and Prowlarr, with nightly restic backup to TrueNAS), FlareSolverr (Cloudflare challenge solver for the indexers)
  - cloud: Nextcloud (cloud storage, with its Postgres and Redis, nightly restic backup to TrueNAS and a nightly one-way sync of the NAS library), OnlyOffice (document server for Nextcloud)
  - photos: Immich (photo library, reached over Tailscale at photos.enricoruggieri.com; originals on the NAS dataset `tank-fast/immich-library` over NFS, own Postgres with VectorChord, Valkey, machine learning on the GPU worker through time-slicing, nightly restic backup of library and DB dump to TrueNAS)
  - ai: Ollama (LLM inference), Open WebUI (chat UI for Ollama), Qdrant (vector database for Open WebUI), ComfyUI (image generation; created at 0 replicas and scaled by hand, outputs on the NAS)
- PVC backups: `apps/<group>/pvc-backup/` has one nightly CronJob per app (02:05-02:45; the PVCs are ReadWriteOnce, so each job runs on the app's node) for Jellyfin, Navidrome, Calibre-Web, Sonarr, Radarr, Prowlarr, Jackett and Open WebUI. They share the script in `k8s-talos/components/pvc-backup/` (SQLite copied with the online backup API, then restic, keeping 7 daily, 4 weekly and 6 monthly). Each app has its own restic repo under the TrueNAS share `backup-pool-2/k8s-pvc`. Not backed up because the data is re-downloaded or rebuilt: Ollama, ComfyUI, Qdrant, the Immich caches, Meilisearch, Redis, Prometheus/Alertmanager and OnlyOffice; Joplin and Transmission are not backed up by choice
- GPU: worker `talos-133` with the RTX 3060 passed through (`gpu = true` in `talos_tf/variables.tf`), NVIDIA LTS driver + container toolkit as Talos extensions, RuntimeClass `nvidia`, nvidia-device-plugin and dcgm-exporter in `nvidia`; the device plugin time-slices the GPU into 4 shares so Ollama, ComfyUI and Immich can run together (no VRAM isolation)

## Quick Start

### Prerequisites
- Proxmox VE node with SSH access
- Terraform, Ansible, kubectl, talosctl, flux, sops installed
- Age encryption key: `~/.sops/age_key.txt`

### Build the cluster

```bash
cd talos_tf
make tf-init && make tf-plan && make tf-apply
make configs   # writes ~/.talos/config and ~/.kube/talos-config

# Flux then reconciles everything under k8s-talos/
flux get kustomizations
```

## License

Personal homelab setup. Adapt as needed for your environment.
