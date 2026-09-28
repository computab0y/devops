#!/usr/bin/env bash
# Start a run: scripts/start-run.sh [clusterAlias] [upload]   (defaults: homelab true)
# ARTIFACTORY_URL overrides the upload base (default: in-cluster Artifactory, generic-local).
set -euo pipefail
cd "$(dirname "$0")/.."
alias="${1:-homelab}"; upload="${2:-true}"; run_id="$(date -u +%Y%m%d-%H%M%S)"
url="${ARTIFACTORY_URL:-http://artifactory.artifactory.svc:8082/artifactory/generic-local/must-gather}/$alias"
pr=$(sed -e "s|ARTIFACTORY_URL|$url|" -e "s/CLUSTER_ALIAS/$alias/g" -e "s/RUN_ID/$run_id/" -e "s/UPLOAD/$upload/" \
  tekton/pipelinerun-template.yaml)
# without an upload the artifactory-auth workspace is left unbound (it's optional)
[ "$upload" = true ] || pr=$(printf '%s\n' "$pr" | sed '/- name: artifactory-auth/,$d')
printf '%s\n' "$pr" | oc create -f - -o jsonpath='{.metadata.name}{"\n"}'
echo "runId=$run_id  (follow: tkn pipelinerun logs -f -n must-gather-pipelines <name>)" >&2
