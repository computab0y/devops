#!/usr/bin/env bash
# Deploy the sanitised must-gather pipeline into namespace must-gather-pipelines.
#
# Needs: oc logged in as cluster-admin; config/mgc-config.yaml + config/canaries.txt
# (copy the *.example files and fill in your cluster's values).
# Optional, for uploads: ARTIFACTORY_USERNAME + ARTIFACTORY_PASSWORD in the environment.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
NS=must-gather-pipelines

for f in config/mgc-config.yaml config/canaries.txt; do
  [ -f "$f" ] || { echo "missing $f - copy ${f%.*}.example.${f##*.} and fill it in" >&2; exit 1; }
done

echo "[1/7] Namespace, service accounts + RBAC, PVC, BuildConfig..."
oc apply -f 00-namespace.yaml -f 01-rbac.yaml -f 02-pvc.yaml -f 03-build.yaml

echo "[2/7] Building the must-gather-clean image (checksum-verified release)..."
oc -n $NS start-build must-gather-clean --from-dir=image --follow --wait >/dev/null
echo "      built $(oc -n $NS get istag must-gather-clean:latest -o jsonpath='{.image.dockerImageReference}')"

echo "[3/7] kubeconfig Secret for oc adm must-gather..."
scripts/create-kubeconfig-secret.sh

echo "[4/7] mgc-config Secret (sanitiser config + canaries)..."
oc create secret generic mgc-config -n $NS \
  --from-file=config.yaml=config/mgc-config.yaml --from-file=canaries.txt=config/canaries.txt \
  --dry-run=client -o yaml | oc apply -f -

echo "[5/7] artifactory-auth Secret..."
if [ -n "${ARTIFACTORY_USERNAME:-}" ] && [ -n "${ARTIFACTORY_PASSWORD:-}" ]; then
  oc create secret generic artifactory-auth -n $NS \
    --from-literal=username="$ARTIFACTORY_USERNAME" --from-file=password=<(printf '%s' "$ARTIFACTORY_PASSWORD") \
    --dry-run=client -o yaml | oc apply -f -
else
  echo "      skipped (ARTIFACTORY_USERNAME/ARTIFACTORY_PASSWORD not set) - runs need upload=false"
fi

echo "[6/7] Tasks + Pipeline..."
oc apply -f tekton/tasks.yaml -f tekton/pipeline.yaml

echo "[7/7] Scheduled runs (CronJob as SA must-gather-scheduler)..."
oc create configmap mg-pipelinerun-template -n $NS --from-file=pipelinerun.yaml=tekton/pipelinerun-template.yaml \
  --dry-run=client -o yaml | oc apply -f -
oc apply -f 04-scheduler.yaml
echo "      schedule: $(oc get cronjob -n $NS must-gather-daily -o jsonpath='{.spec.schedule} {.spec.timeZone}')"

echo ""
echo "Done. Runs start daily from the CronJob; to start one now:"
echo "  scripts/start-run.sh <clusterAlias> true    # upload to Artifactory"
echo "  scripts/start-run.sh <clusterAlias> false   # keep on the PVC only"
