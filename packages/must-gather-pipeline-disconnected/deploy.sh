#!/usr/bin/env bash
# Deploy the disconnected must-gather pipeline on the cluster `oc` is logged in to.
#   Needs: local/03-settings.yaml (from 03-settings.example.yaml)
#          ARTIFACTORY_USERNAME / ARTIFACTORY_PASSWORD  (search + upload)
#   Optional: ARTIFACTORY_CA_FILE (PEM, if Artifactory's cert isn't publicly trusted)
#             NAMESPACE (default must-gather-pipelines)
#             CLI_IMAGE / MGC_IMAGE  pull specs in Artifactory (else the pipeline defaults)
# Then register clusters with scripts/target-kubeconfig.sh + scripts/add-cluster.sh.
set -euo pipefail
cd "$(dirname "$0")"
NS="${NAMESPACE:-must-gather-pipelines}"
# print each file as its own YAML document, with the namespace swapped in
ns() { for f in "$@"; do echo "---"; sed "s/namespace: must-gather-pipelines/namespace: $NS/g; s/^  name: must-gather-pipelines$/  name: $NS/" "$f"; done; }
[ -f local/03-settings.yaml ] || { echo "create local/03-settings.yaml from 03-settings.example.yaml first" >&2; exit 1; }
[ -n "${ARTIFACTORY_USERNAME:-}" ] && [ -n "${ARTIFACTORY_PASSWORD:-}" ] || { echo "set ARTIFACTORY_USERNAME and ARTIFACTORY_PASSWORD" >&2; exit 1; }

echo "[1/5] namespace $NS, service account, PVC..."
ns 00-namespace.yaml 01-rbac.yaml 02-pvc.yaml | oc apply -f -

echo "[2/5] settings ConfigMap..."
ns local/03-settings.yaml | oc apply -f -

echo "[3/5] Artifactory credentials (+ CA)..."
oc create secret generic artifactory-auth -n "$NS" --from-literal=username="$ARTIFACTORY_USERNAME" \
  --from-file=password=<(printf '%s' "$ARTIFACTORY_PASSWORD") --dry-run=client -o yaml | oc apply -f -
if [ -n "${ARTIFACTORY_CA_FILE:-}" ]; then
  oc create configmap artifactory-ca -n "$NS" --from-file=ca.crt="$ARTIFACTORY_CA_FILE" --dry-run=client -o yaml | oc apply -f -
  echo "      CA stored in ConfigMap artifactory-ca - bind it to the ca-bundle workspace (README)"
fi
for s in mg-target-clusters mg-sanitise-config; do   # empty until add-cluster.sh fills them
  oc get secret "$s" -n "$NS" >/dev/null 2>&1 || oc create secret generic "$s" -n "$NS" --save-config >/dev/null
done

echo "[4/5] Tasks + Pipeline..."
pipe=$(ns tekton/pipeline.yaml)
[ -n "${CLI_IMAGE:-}" ] && pipe=$(printf '%s\n' "$pipe" | python3 -c 'import sys,re,os;s=sys.stdin.read();print(re.sub(r"(- name: cliImage\n(?:.*\n)*?\s+default: ).*",r"\g<1>"+os.environ["CLI_IMAGE"],s,count=1),end="")')
[ -n "${MGC_IMAGE:-}" ] && pipe=$(printf '%s\n' "$pipe" | python3 -c 'import sys,re,os;s=sys.stdin.read();print(re.sub(r"(- name: mgcImage\n(?:.*\n)*?\s+default: ).*",r"\g<1>"+os.environ["MGC_IMAGE"],s,count=1),end="")')
ns tekton/tasks.yaml | oc apply -f -
printf '%s\n' "$pipe" | oc apply -f -

echo "[5/5] check: can the pipeline reach and search Artifactory?"
art=$(oc get configmap mg-settings -n "$NS" -o jsonpath='{.data.ARTIFACTORY_URL}')
repo=$(oc get configmap mg-settings -n "$NS" -o jsonpath='{.data.DOCKER_REPO}')
echo "      (run scripts/start-run.sh after adding a cluster - the resolve-image task reports what it finds in $art, repo $repo)"
echo "Done. Next: scripts/target-kubeconfig.sh + scripts/add-cluster.sh for each cluster (README step 5)."
