#!/usr/bin/env bash
# Run while `oc` is logged in to a TARGET cluster as cluster-admin. Creates the identity
# must-gather uses there (SA must-gather-runner + cluster-admin + long-lived token, in
# namespace must-gather-access) and writes config/<name>.kubeconfig for add-cluster.sh.
#
#   scripts/target-kubeconfig.sh <name> [api-url]
#     name     short cluster name used in the pipeline (letters, digits, -)
#     api-url  API URL as reachable FROM THE PIPELINE CLUSTER (default: current server;
#              use https://kubernetes.default.svc when the target IS the pipeline cluster)
#   CA_FILE=<pem>  CA for that URL if it isn't the cluster's own (e.g. a custom API cert)
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:?usage: target-kubeconfig.sh <name> [api-url]}"; api="${2:-$(oc whoami --show-server)}"
[[ "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "name must be lowercase letters, digits and -" >&2; exit 1; }
NS=must-gather-access
oc apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Namespace
metadata: { name: $NS }
---
apiVersion: v1
kind: ServiceAccount
metadata: { name: must-gather-runner, namespace: $NS }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: must-gather-runner-cluster-admin }
roleRef: { apiGroup: rbac.authorization.k8s.io, kind: ClusterRole, name: cluster-admin }
subjects: [ { kind: ServiceAccount, name: must-gather-runner, namespace: $NS } ]
---
apiVersion: v1
kind: Secret
metadata:
  name: must-gather-runner-token
  namespace: $NS
  annotations: { kubernetes.io/service-account.name: must-gather-runner }
type: kubernetes.io/service-account-token
YAML
for _ in $(seq 1 30); do [ -n "$(oc get secret -n $NS must-gather-runner-token -o jsonpath='{.data.token}')" ] && break; sleep 2; done
umask 077; mkdir -p config; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [ -n "${CA_FILE:-}" ]; then cp "$CA_FILE" "$tmp/ca.crt"; else
  oc get secret -n $NS must-gather-runner-token -o jsonpath='{.data.ca\.crt}' | base64 -d > "$tmp/ca.crt"; fi
K="config/$name.kubeconfig"; rm -f "$K"
KUBECONFIG=$K oc config set-cluster "$name" --server="$api" --certificate-authority="$tmp/ca.crt" --embed-certs=true >/dev/null
KUBECONFIG=$K oc config set-credentials must-gather-runner \
  --token="$(oc get secret -n $NS must-gather-runner-token -o jsonpath='{.data.token}' | base64 -d)" >/dev/null
KUBECONFIG=$K oc config set-context "$name" --cluster="$name" --user=must-gather-runner >/dev/null
KUBECONFIG=$K oc config use-context "$name" >/dev/null
chmod 600 "$K"
echo "wrote $K (server $api). Next: scripts/add-cluster.sh $name"
