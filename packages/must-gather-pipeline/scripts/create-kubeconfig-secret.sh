#!/usr/bin/env bash
# Build Secret must-gather-pipelines/must-gather-kubeconfig (key: kubeconfig) from the
# must-gather-runner SA token. Points at the in-cluster API (https://kubernetes.default.svc)
# because the pipeline gathers from the cluster it runs on. Prints no secret material.
set -euo pipefail
NS=must-gather-pipelines
for _ in $(seq 1 30); do
  [ -n "$(oc get secret -n $NS must-gather-runner-token -o jsonpath='{.data.token}')" ] && break; sleep 2
done
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; chmod 700 "$tmp"
oc get secret -n $NS must-gather-runner-token -o jsonpath='{.data.ca\.crt}' | base64 -d > "$tmp/ca.crt"
K="$tmp/kubeconfig"
KUBECONFIG=$K oc config set-cluster in-cluster --server=https://kubernetes.default.svc \
  --certificate-authority="$tmp/ca.crt" --embed-certs=true >/dev/null
KUBECONFIG=$K oc config set-credentials must-gather-runner \
  --token="$(oc get secret -n $NS must-gather-runner-token -o jsonpath='{.data.token}' | base64 -d)" >/dev/null
KUBECONFIG=$K oc config set-context gather --cluster=in-cluster --user=must-gather-runner >/dev/null
KUBECONFIG=$K oc config use-context gather >/dev/null
oc create secret generic must-gather-kubeconfig -n $NS --from-file=kubeconfig="$K" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null
echo "secret/$NS/must-gather-kubeconfig ready (server https://kubernetes.default.svc)"
