#!/usr/bin/env bash
# Start a run: scripts/start-run.sh [clusterAlias] [upload] [gatherType] [includeDefault]
#   defaults: homelab true default true
#   gatherType: default | acm | logging | acs | odf | oadp | gitops | custom
#   (custom: set MUST_GATHER_IMAGES="img1 img2")
# ARTIFACTORY_URL overrides the upload base (default: in-cluster Artifactory, generic-local).
set -euo pipefail
cd "$(dirname "$0")/.."
alias="${1:-homelab}"; upload="${2:-true}"; gtype="${3:-default}"; incdef="${4:-true}"
run_id="$(date -u +%Y%m%d-%H%M%S)"
url="${ARTIFACTORY_URL:-http://artifactory.artifactory.svc:8082/artifactory/generic-local/must-gather}"  # task appends /<alias>
pr=$(sed -e "s|ARTIFACTORY_URL|$url|" -e "s/CLUSTER_ALIAS/$alias/g" -e "s/RUN_ID/$run_id/" -e "s/UPLOAD/$upload/" \
  -e "s/GATHER_TYPE/$gtype/" -e "s/INCLUDE_DEFAULT/$incdef/" tekton/pipelinerun-template.yaml)
if [ "$gtype" = custom ]; then
  [ -n "${MUST_GATHER_IMAGES:-}" ] || { echo "gatherType=custom needs MUST_GATHER_IMAGES" >&2; exit 1; }
  pr=$(printf '%s\n' "$pr" | sed "s|^  params:|  params:\n    - { name: mustGatherImages, value: \"$MUST_GATHER_IMAGES\" }|")
fi
# without an upload the artifactory-auth workspace is left unbound (it's optional)
[ "$upload" = true ] || pr=$(printf '%s\n' "$pr" | sed '/- name: artifactory-auth/,$d')
printf '%s\n' "$pr" | oc create -f - -o jsonpath='{.metadata.name}{"\n"}'
echo "runId=$run_id  (follow: tkn pipelinerun logs -f -n must-gather-pipelines <name>)" >&2
