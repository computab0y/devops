#!/usr/bin/env python3
"""Run every query in the generated dashboard against Thanos/Prometheus and report empty ones.

    python3 tools/check_dashboard.py --cluster homelab --group homelab-pgd [--target homelab-pgd-1]

Uses the thanos-querier route in openshift-monitoring and your own `oc whoami -t`
token (you need cluster-monitoring-view or similar). Pass --url for another Prometheus.
"""
import argparse
import json
import os
import re
import ssl
import subprocess
import sys
import urllib.parse
import urllib.request

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--cluster", required=True)
ap.add_argument("--group", required=True)
ap.add_argument("--target", help="node for the 'Move leader to' variable (default: first non-leader)")
ap.add_argument("--namespace", help="namespace of the pgd-demo app (default: read from pgd_demo_info)")
ap.add_argument("--url", help="Prometheus API base URL (default: thanos-querier route)")
a = ap.parse_args()

oc = lambda *args: subprocess.run(["oc", *args], check=True, capture_output=True, text=True).stdout.strip()  # noqa
url = a.url or "https://" + oc("get", "route", "thanos-querier", "-n", "openshift-monitoring",
                               "-o", "jsonpath={.spec.host}")
token = oc("whoami", "-t")
ctx = ssl._create_unverified_context()


def run(expr, target):
    e = (expr.replace("$namespace", a.namespace or "")
         .replace("$cluster", a.cluster).replace("$group", a.group)
         .replace("$target", target or "").replace("$__range", "1h"))
    req = urllib.request.Request(f"{url}/api/v1/query", data=urllib.parse.urlencode({"query": e}).encode(),
                                 headers={"Authorization": f"Bearer {token}"})
    return json.load(urllib.request.urlopen(req, context=ctx))["data"]["result"]


d = yaml.safe_load(open(os.path.join(HERE, "..", "dashboard", "grafana-dashboard.yaml")))
dash = json.loads(d["spec"]["json"])
variables = {v["name"]: v for v in dash["templating"]["list"]}

if not a.namespace:
    a.namespace = next((r["metric"].get("namespace") for r in run(
        f'pgd_demo_info{{cluster="{a.cluster}", group="{a.group}"}}', None)), "")
tq = variables["target"]["query"]["query"]
targets = sorted({r["metric"]["target"] for r in run(re.sub(r"^query_result\((.*)\)$", r"\1", tq), None)})
target = a.target or (targets[0] if targets else None)
print(f"cluster={a.cluster} group={a.group} namespace={a.namespace} target={target} (choices: {targets})\n")

empty = 0
for p in dash["panels"]:
    for t in p.get("targets", []):
        res = run(t["expr"], target)
        allowed = p["fieldConfig"]["defaults"].get("noValue")  # panel says what "no data" means
        empty += not res and not allowed
        status = "ok" if res else ("ok*" if allowed else "EMPTY")
        note = f"  (no data: {allowed})" if not res and allowed else ""
        print(f"{status:5} {p['title'][:50]:50} {t['refId']} rows={len(res)}{note}")
for name in ("cluster", "group", "namespace", "app_url", "pgadmin_url"):
    m = re.match(r"label_values\((.*), (\w+)\)$", variables[name]["query"]["query"])
    vals = sorted({r["metric"].get(m.group(2)) for r in run(m.group(1), target)})
    empty += not vals
    print(f"{'EMPTY' if not vals else 'ok':5} variable ${name}: {vals}")
print(f"\n{empty} empty")
sys.exit(1 if empty else 0)
