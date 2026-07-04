#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${1:-openshift-pipelines-operator}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Deploying ftp-file-pipeline to namespace: ${NAMESPACE}"

# Update namespace in all YAMLs
apply() {
  sed "s/namespace: openshift-pipelines-operator/namespace: ${NAMESPACE}/g" "$1" | oc apply -f -
}

echo "[1/5] Applying ConfigMap..."
apply "${SCRIPT_DIR}/pipeline-config.yaml"

echo "[2/5] Applying Secrets..."
apply "${SCRIPT_DIR}/vault-token-secret.yaml"
apply "${SCRIPT_DIR}/ftp-vm-ssh-key-secret.yaml"

echo "[3/5] Applying Task..."
apply "${SCRIPT_DIR}/ftp-operations-task.yaml"

echo "[4/5] Applying Pipeline..."
apply "${SCRIPT_DIR}/ftp-file-pipeline.yaml"

echo "[5/5] Enabling pipelines-console-plugin (for enum dropdowns in the console)..."
oc patch console.operator cluster --type=merge \
  -p '{"spec":{"plugins":["pipelines-console-plugin"]}}' 2>/dev/null || true

echo ""
echo "Done. Run keycloak-vault-sync first to populate Vault and the username dropdown, then:"
echo "  tkn pipeline start ftp-file-pipeline -n ${NAMESPACE}"
echo ""
echo "Or via OCP console: Pipelines → ftp-file-pipeline → Start"
