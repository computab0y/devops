#!/usr/bin/env bash
# Copy a run's tarball (+ .sha256) off the PVC into this folder and verify it.
#   scripts/fetch-archive.sh <targetCluster> <runId>      (NAMESPACE=... to override)
set -euo pipefail
cd "$(dirname "$0")/.."
NS="${NAMESPACE:-must-gather-pipelines}"; cluster="$1"; run_id="$2"
src="/data/${cluster}/${run_id}/archive"; pod="mg-fetch-${run_id//[^0-9a-z]/}"
img=$(oc get pipeline sanitised-must-gather -n "$NS" -o jsonpath='{.spec.params[?(@.name=="mgcImage")].default}')
trap 'oc delete pod -n $NS "$pod" --ignore-not-found --wait=false >/dev/null' EXIT
oc apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: { name: $pod, namespace: $NS }
spec:
  serviceAccountName: must-gather-tasks
  restartPolicy: Never
  terminationGracePeriodSeconds: 1
  containers:
    - name: fetch
      image: $img
      command: [sleep, "600"]
      securityContext:
        allowPrivilegeEscalation: false
        runAsNonRoot: true
        capabilities: { drop: [ALL] }
        seccompProfile: { type: RuntimeDefault }
      volumeMounts: [{ name: data, mountPath: /data, readOnly: true }]
  volumes:
    - name: data
      persistentVolumeClaim: { claimName: must-gather-data, readOnly: true }
YAML
oc wait -n "$NS" --for=condition=Ready "pod/$pod" --timeout=180s >/dev/null
name=$(oc exec -n "$NS" "$pod" -- sh -c "cd $src && ls *-must-gather-sanitised.tar.gz" | head -1)
[ -n "$name" ] || { echo "no archive in $src" >&2; exit 1; }
for f in "$name" "$name.sha256"; do oc cp -n "$NS" "$pod:$src/$f" "./$f" >/dev/null; done
shasum -a 256 -c "$name.sha256"
