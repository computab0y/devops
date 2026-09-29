#!/usr/bin/env bash
# Copy a run's sanitised tarball (+ .sha256) from the PVC to this folder via a short-lived
# restricted pod, verify the checksum, then delete the pod.
#   scripts/fetch-archive.sh <clusterAlias> <runId>
set -euo pipefail
cd "$(dirname "$0")/.."
NS=must-gather-pipelines; alias="$1"; run_id="$2"
src="/data/${alias}/${run_id}/archive"
pod="mg-fetch-${run_id//[^0-9a-z]/}"
img="image-registry.openshift-image-registry.svc:5000/$NS/must-gather-clean:latest"
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
oc wait -n $NS --for=condition=Ready "pod/$pod" --timeout=180s >/dev/null
# archive name includes the gather type: <alias>-<runId>[-<type>]-must-gather-sanitised.tar.gz
name=$(oc exec -n $NS "$pod" -- sh -c "cd $src && ls *-must-gather-sanitised.tar.gz" | head -1)
[ -n "$name" ] || { echo "no archive found in $src" >&2; exit 1; }
for f in "$name" "$name.sha256"; do oc cp -n $NS "$pod:$src/$f" "./$f" >/dev/null; done
shasum -a 256 -c "$name.sha256"
ls -l "$name"
