#!/bin/bash
# Helper script to migrate remaining Sealed Secrets to SOPS Secrets
# Usage: ./migrate-secrets-to-sops.sh <secret-path>
# Example: ./migrate-secrets-to-sops.sh k8s/tooling/prometheus/secret.yaml

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <path-to-secret.yaml>"
  echo "Example: $0 k8s/tooling/prometheus/secret.yaml"
  exit 1
fi

SECRET_FILE="$1"
DIR=$(dirname "$SECRET_FILE")
SOPS_FILE="${DIR}/sops_secret.yaml"
SEALED_FILE="${DIR}/sealed_secret.yaml"

if [ ! -f "$SECRET_FILE" ]; then
  echo "Error: $SECRET_FILE not found"
  exit 1
fi

# Step 1: Read the plaintext secret and create SopsSecret
echo "Step 1: Creating SopsSecret from plaintext secret..."
echo "      Converting $SECRET_FILE to $SOPS_FILE"

# Extract metadata
NAMESPACE=$(grep "namespace:" "$SECRET_FILE" | awk '{print $2}' | head -1)
SECRET_NAME=$(grep "^  name:" "$SECRET_FILE" | awk '{print $2}' | head -1)
APP_NAME=$(basename "$DIR")

# Create the SopsSecret (template) - you'll need to manually add the data values
cat > "$SOPS_FILE" << SOPS_EOF
apiVersion: isindir.github.com/v1alpha3
kind: SopsSecret
metadata:
  name: ${APP_NAME}-sops
  namespace: ${NAMESPACE}
spec:
  secretTemplates:
    - name: ${SECRET_NAME}
      labels:
        app: ${APP_NAME}
      stringData:
        # ADD THE ACTUAL SECRET VALUES HERE - copy from $SECRET_FILE
SOPS_EOF

echo "✓ Created $SOPS_FILE (template)"
echo "  Edit this file and add the secret values from $SECRET_FILE under 'stringData'"
echo ""

# Step 2: Encrypt
echo "Step 2: Encrypting with SOPS..."
SOPS_AGE_KEY_FILE=./age_key.txt sops -e -i "$SOPS_FILE"
echo "✓ Encrypted $SOPS_FILE"
echo ""

# Step 3: Comment out sealed_secret
echo "Step 3: Commenting out sealed_secret..."
if [ -f "$SEALED_FILE" ]; then
  # Add comment header if not present
  if ! head -1 "$SEALED_FILE" | grep -q "^#"; then
    sed -i '' '1s/^/# Migrated to SopsSecret\n# See sops_secret.yaml\n#\n/' "$SEALED_FILE"
    sed -i '' 's/^/# /' "$SEALED_FILE"
  fi
  echo "✓ Commented out $SEALED_FILE"
else
  echo "⚠ No sealed_secret.yaml found at $SEALED_FILE"
fi
echo ""

echo "Next steps:"
echo "  1. Review the changes: git diff $DIR"
echo "  2. Commit: git add $DIR && git commit -m 'Migrate ${APP_NAME} secret to SOPS'"
echo "  3. Push to GitHub"
echo "  4. Monitor: ArgoCD will sync and SOPS operator will create the K8s Secret"
