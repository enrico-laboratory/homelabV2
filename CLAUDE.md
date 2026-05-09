# CLAUDE.md - Homelab

Infrastructure-as-code repository for managing a self-hosted Kubernetes/virtualization homelab with Proxmox, networking, and monitoring infrastructure.

## File name convention

{Composer Last Name}, {Composer names} - {Music score title} {Eventual specifics}

## SOPS + Age Key Management

### Age Key Location
The age private key is stored at: **`~/.sops/age_key.txt`** (user's home directory, not in repo)

### Encrypting Kubernetes Secrets with SOPS

**Always use selective encryption** with the `--encrypted-regex` flag to encrypt only `stringData` fields. This keeps the YAML structure readable in git.

#### Proper encryption command:
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --encrypt --in-place --encrypted-regex '^(stringData)$' k8s/{namespace}/{app}/sops_secret.yaml
```

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
            key2: plaintext-value-2
```

2. **Encrypt with selective regex**:
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --encrypt --in-place --encrypted-regex '^(stringData)$' k8s/{namespace}/{app}/sops_secret.yaml
```

3. **Verify encryption** (should decrypt and show plaintext):
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --decrypt k8s/{namespace}/{app}/sops_secret.yaml
```

4. **Commit encrypted file** — only `stringData` values will be encrypted, structure remains readable

### Decrypting existing secrets:
```bash
export SOPS_AGE_KEY_FILE=~/.sops/age_key.txt
sops --decrypt k8s/{namespace}/{app}/sops_secret.yaml
```

### Why selective encryption (`--encrypted-regex '^(stringData)$'`)?
- Keeps YAML structure, keys, and metadata readable in git diffs
- Only sensitive values are encrypted
- Follows the `isindir/sops-secrets-operator` pattern used in this repo
- Makes code review easier while protecting secrets

## Rules

- **Never use `kubectl` to create resources** — let ArgoCD manage all deployments. Only use kubectl for testing/debugging, never for persistent state changes.
- Every time that a new application is added in Kubernetes, update the README.md. Exclude Sonarr, radarr and transmission