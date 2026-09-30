#!/usr/bin/env bash
# scripts/start-run.sh <targetCluster> [gatherType] [includeDefault] [imageTag] [upload]
#   defaults: default true auto true            (NAMESPACE=... to override)
set -euo pipefail
cd "$(dirname "$0")/.."
NS="${NAMESPACE:-must-gather-pipelines}"
cluster="${1:?usage: start-run.sh <targetCluster> [gatherType] [includeDefault] [imageTag] [upload]}"
pr=$(sed -e "s/namespace: must-gather-pipelines/namespace: $NS/" -e "s/TARGET_CLUSTER/$cluster/" \
    -e "s/GATHER_TYPE/${2:-default}/" -e "s/INCLUDE_DEFAULT/${3:-true}/" -e "s/IMAGE_TAG/${4:-auto}/" \
    -e "s/UPLOAD/${5:-true}/" tekton/pipelinerun-template.yaml)
# private Artifactory CA stored by deploy.sh -> bind it to the ca-bundle workspace
if oc get configmap artifactory-ca -n "$NS" >/dev/null 2>&1; then
  pr="$pr
    - name: ca-bundle
      configMap:
        name: artifactory-ca"
fi
printf '%s\n' "$pr" | oc create -f - -o jsonpath='{.metadata.name}{"\n"}'
echo "follow: tkn pipelinerun logs -f -n $NS <name>" >&2
