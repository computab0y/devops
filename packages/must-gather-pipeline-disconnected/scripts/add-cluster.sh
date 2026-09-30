#!/usr/bin/env bash
# Register a target cluster with the pipeline (run while `oc` is logged in to the
# PIPELINE cluster):
#   - adds config/<name>.kubeconfig to Secret mg-target-clusters
#   - adds config/<name>.config.yaml + config/<name>.canaries.txt to Secret mg-sanitise-config
#     (falls back to config/default.* if the cluster has none)
#   - updates the targetCluster dropdown (live Pipeline + tekton/pipeline.yaml, so a later
#     deploy.sh keeps it)
#
#   scripts/add-cluster.sh <name>        (NAMESPACE=... to override must-gather-pipelines)
set -euo pipefail
cd "$(dirname "$0")/.."
NS="${NAMESPACE:-must-gather-pipelines}"; name="${1:?usage: add-cluster.sh <name>}"
[ -s "config/$name.kubeconfig" ] || { echo "missing config/$name.kubeconfig - create it with scripts/target-kubeconfig.sh" >&2; exit 1; }
for f in config.yaml canaries.txt; do
  [ -s "config/$name.$f" ] || [ -s "config/default.$f" ] || { echo "missing config/$name.$f (or config/default.$f) - copy config/example.$f" >&2; exit 1; }
done
umask 077; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# merge a file into a Secret without putting its contents on a command line
merge() {  # merge <secret> <key> <file>
  mkdir -p "$tmp/$1"
  oc extract "secret/$1" -n "$NS" --to="$tmp/$1" >/dev/null 2>&1 || true
  cp "$3" "$tmp/$1/$2"
  oc create secret generic "$1" -n "$NS" --from-file="$tmp/$1" --dry-run=client -o yaml | oc apply -f - >/dev/null
}
merge mg-target-clusters "$name.kubeconfig" "config/$name.kubeconfig"
for f in config.yaml canaries.txt; do
  src="config/$name.$f"; [ -s "$src" ] || src="config/default.$f"
  merge mg-sanitise-config "$(basename "$src")" "$src"
done

# dropdown = every cluster that has a kubeconfig in the Secret
clusters=$(oc get secret mg-target-clusters -n "$NS" -o go-template='{{range $k, $v := .data}}{{$k}}{{"\n"}}{{end}}' \
  | sed -n 's/\.kubeconfig$//p' | sort)
python3 - "$clusters" <<'PY'
import json, sys, re
names = sys.argv[1].split()
p = "tekton/pipeline.yaml"; s = open(p).read()
s, n = re.subn(r'(# add-cluster.sh rewrites this list - keep it on one line.\n\s+enum: ).*', r'\g<1>' + json.dumps(names), s)
assert n == 1, "enum marker not found in tekton/pipeline.yaml"
open(p, "w").write(s)
PY
# patch only the dropdown on the live Pipeline (a full re-apply would reset image overrides)
idx=$(oc get pipeline sanitised-must-gather -n "$NS" -o go-template='{{range $i, $p := .spec.params}}{{if eq $p.name "targetCluster"}}{{$i}}{{end}}{{end}}')
[ -n "$idx" ] || { echo "Pipeline sanitised-must-gather not found in $NS - run deploy.sh first" >&2; exit 1; }
oc patch pipeline sanitised-must-gather -n "$NS" --type json \
  -p "[{\"op\":\"replace\",\"path\":\"/spec/params/$idx/enum\",\"value\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1].split()))' "$clusters")}]" >/dev/null
echo "clusters in the targetCluster dropdown: $(echo $clusters)"
