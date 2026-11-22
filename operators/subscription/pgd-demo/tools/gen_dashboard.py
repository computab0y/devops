#!/usr/bin/env python3
"""Generate the GrafanaDashboard CR for the PGD write-leader lab (app sections 2-4).

    python3 tools/gen_dashboard.py            # writes dashboard/grafana-dashboard.yaml

The dashboard holds no cluster-specific values: datasource, cluster and PGD group are
dashboard variables, and nodes / write leader / Raft leaders come from the app's metrics.
Edit this script (not the generated YAML) and re-run it.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "dashboard", "grafana-dashboard.yaml")

DS = {"type": "prometheus", "uid": "${datasource}"}
SEL = 'cluster="$cluster", group="$group"'
_id = [0]


def s(metric, extra=""):
    """metric{cluster=..., group=..., extra}"""
    return f"{metric}{{{SEL}{', ' + extra if extra else ''}}}"


def nid():
    _id[0] += 1
    return _id[0]


def tgt(expr, ref="A", legend="", instant=False):
    t = {"datasource": DS, "expr": expr, "refId": ref, "legendFormat": legend or "__auto"}
    if instant:
        t.update({"instant": True, "range": False, "format": "table"})
    else:
        t.update({"instant": False, "range": True})
    return t


def vmap(pairs):
    """pairs: list of (value, text, color)"""
    return [{"type": "value", "options": {str(v): {"text": t, "color": c, "index": i}
                                          for i, (v, t, c) in enumerate(pairs)}}]


def thresholds(*steps):
    return {"mode": "absolute", "steps": [{"color": c, "value": v} for v, c in steps]}


def row(title, y):
    return {"type": "row", "id": nid(), "title": title, "collapsed": False,
            "gridPos": {"x": 0, "y": y, "w": 24, "h": 1}, "panels": []}


def panel(ptype, title, x, y, w, h, targets, desc="", defaults=None, overrides=None, options=None,
          transformations=None):
    return {"type": ptype, "id": nid(), "title": title, "description": desc, "datasource": DS,
            "gridPos": {"x": x, "y": y, "w": w, "h": h}, "targets": targets,
            "fieldConfig": {"defaults": defaults or {}, "overrides": overrides or []},
            "options": options or {}, "transformations": transformations or []}


def stat(title, x, y, w, h, targets, desc="", defaults=None, text_mode="auto", color_mode="background"):
    # Stats need time_series format: table format ignores legendFormat, so every
    # stat would be labelled with the column name "Value" instead of {{node}} etc.
    for t in targets:
        if t.get("format") == "table":
            t["format"] = "time_series"
    return panel("stat", title, x, y, w, h, targets, desc, defaults,
                 options={"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                          "textMode": text_mode, "colorMode": color_mode, "graphMode": "none",
                          "justifyMode": "center", "orientation": "auto", "wideLayout": True})


def ov(name, props):
    return {"matcher": {"id": "byName", "options": name},
            "properties": [{"id": k, "value": v} for k, v in props.items()]}


def table(title, x, y, w, h, targets, desc="", overrides=None, transformations=None, sort=None):
    return panel("table", title, x, y, w, h, targets, desc,
                 defaults={"custom": {"align": "auto", "cellOptions": {"type": "auto"}}},
                 overrides=overrides, transformations=transformations,
                 options={"showHeader": True, "cellHeight": "sm",
                          "footer": {"show": False, "reducer": ["sum"], "fields": ""},
                          "sortBy": sort or []})


def timeseries(title, x, y, w, h, targets, desc="", unit="short", th=None, no_value=None):
    d = {"unit": unit, **({"noValue": no_value} if no_value else {}), "custom": {"drawStyle": "line", "lineWidth": 2, "fillOpacity": 10,
                                  "showPoints": "never", "spanNulls": False}}
    if th:
        d["thresholds"] = th
        d["custom"]["thresholdsStyle"] = {"mode": "dashed"}
    return panel("timeseries", title, x, y, w, h, targets, desc, d,
                 options={"legend": {"displayMode": "table", "placement": "right",
                                     "calcs": ["lastNotNull", "max"]},
                          "tooltip": {"mode": "multi", "sort": "desc"}})


def timeline(title, x, y, w, h, targets, mappings, desc=""):
    return panel("state-timeline", title, x, y, w, h, targets, desc,
                 defaults={"mappings": mappings, "color": {"mode": "thresholds"},
                           "thresholds": thresholds((None, "text")),
                           "custom": {"fillOpacity": 80, "lineWidth": 0}},
                 options={"showValue": "never", "mergeValues": True, "rowHeight": 0.8,
                          "alignValue": "center", "legend": {"showLegend": True, "displayMode": "list",
                                                             "placement": "bottom"},
                          "tooltip": {"mode": "single"}})


def merge_organize(exclude, rename, order=None):
    return [{"id": "merge", "options": {}},
            {"id": "organize", "options": {"excludeByName": {k: True for k in exclude},
                                           "renameByName": rename, "indexByName": order or {}}}]


def query_var(name, label, query, regex="", hide=0, sort=1):
    return {"name": name, "label": label, "type": "query", "datasource": DS,
            "query": {"query": query, "refId": f"PrometheusVariableQueryEditor-{name}", "qryType": 3},
            "definition": query, "regex": regex, "refresh": 2, "sort": sort,
            "includeAll": False, "multi": False, "current": {}, "options": [], "hide": hide}


VERDICT_MAP = vmap([(-1, "current write leader", "blue"), (0, "SAFE", "green"),
                    (1, "WAIT (use strict)", "orange"), (2, "UNSAFE", "red")])
KIND_MAP = vmap([("local", "local", "orange")])
LEADER_STAT = {"color": {"mode": "fixed", "fixedColor": "blue"}, "noValue": "none"}
RAFT_LEADER = s("pgd_demo_raft_leader", 'scope="data group"')
RAFT_PARENT = s("pgd_demo_raft_leader", 'scope="parent group"')
LOCAL_MAX = s("pgd_demo_table_max_id", 'kind="local"')
LOCAL_LAST = s("pgd_demo_sequence_last_value", 'kind="local"')
VERDICT_T = s("pgd_demo_switch_verdict", 'target="$target"')
CHECK_T = s("pgd_demo_switch_check_status", 'target="$target"')

HEALTH_MAP = vmap([(0, "HEALTHY", "green"), (1, "WARNING", "orange"), (2, "CRITICAL", "red")])
CHECK_MAP = vmap([(0, "OK", "green"), (1, "WARNING", "orange"), (2, "CRITICAL", "red"), (3, "UNKNOWN", "purple")])
ISSUE_MAP = vmap([(1, "WARNING", "orange"), (2, "CRITICAL", "red")])
YES_NO = vmap([(1, "yes", "green"), (0, "NO", "red")])
TEXT_STAT = {"color": {"mode": "fixed", "fixedColor": "text"}}
OK_REGEX = lambda ok: (vmap([(ok, ok, "green")]) +  # noqa: E731
                       [{"type": "regex", "options": {"pattern": ".*", "result": {"color": "red", "index": 1}}}])

panels = []

# ------------------------------------------------------------------ overview
y = 0
panels.append(row("Overview: PGD health, replication, leaders and sequences", y))
y += 1
panels += [
    stat("PGD health", 0, y, 6, 5, [tgt(f"max({s('pgd_demo_overall_health')})", instant=True)],
         "Worst of: PGD's monitoring functions (bdr.monitor_group_raft, bdr.monitor_group_versions, "
         "bdr.monitor_local_replslots on every node), node reachability, replication slots and subscriptions, "
         "and the EDB operator's Ready condition. 'Open issues' lists what's behind a WARNING or CRITICAL.",
         {"mappings": HEALTH_MAP, "noValue": "app down", "color": {"mode": "thresholds"},
          "thresholds": thresholds((None, "green"), (1, "orange"), (2, "red"))}),
    stat("Write leader", 6, y, 6, 5,
         [tgt(f"max by (node) ({s('pgd_demo_write_leader')} == 1)", legend="{{node}}", instant=True)],
         "Node the Connection Manager / PGD Proxy routes writes to (bdr.node_group_routing_summary.write_lead).",
         LEADER_STAT, text_mode="name"),
    stat("Raft leader: data group", 12, y, 6, 5,
         [tgt(f"max by (node) ({RAFT_LEADER} == 1)", legend="{{node}}", instant=True)],
         "Raft leader of the data group (bdr.group_raft_details). It runs write-leader elections and routing, "
         "and is often not the write leader.",
         {"color": {"mode": "fixed", "fixedColor": "purple"}, "noValue": "none",
          "links": [{"title": "Run safety checks & move this Raft leader", "url": "${app_url}/switch?kind=raft-data", "targetBlank": True}]}, text_mode="name"),
    stat("Raft leader: parent group", 18, y, 6, 5,
         [tgt(f"max by (node) ({RAFT_PARENT} == 1)", legend="{{node}}", instant=True)],
         "Raft leader of the top-level group, which hands out galloc chunks and serialises global DDL locks.",
         {"color": {"mode": "fixed", "fixedColor": "purple"}, "noValue": "none",
          "links": [{"title": "Run safety checks & move this Raft leader", "url": "${app_url}/switch?kind=raft-parent", "targetBlank": True}]}, text_mode="name"),
]
y += 5
panels += [
    table("Nodes: status", 0, y, 12, 8, [
        tgt(f"max by (node, kind, state) ({s('pgd_demo_node_info')})", "A", instant=True),
        tgt(f"max by (node) ({s('pgd_demo_node_reachable')})", "B", instant=True),
        tgt(f"max by (node) ({s('pgd_demo_write_leader')})", "C", instant=True),
        tgt(f"max by (node) ({RAFT_LEADER})", "D", instant=True),
        tgt(f"time() - max by (node) ({s('pgd_demo_node_start_time_seconds')})", "E", instant=True)],
        "Every node in the group: kind and PGD peer state (bdr.node_summary), whether the app can reach it "
        "directly, its leader roles, and Postgres uptime (pg_postmaster_start_time()).",
        overrides=[
            ov("state", {"mappings": OK_REGEX("ACTIVE"), "custom.cellOptions": {"type": "color-text"}}),
            ov("reachable", {"mappings": YES_NO, "custom.cellOptions": {"type": "color-text"}}),
            ov("write", {"mappings": vmap([(1, "WRITE LEADER", "blue"), (0, " ", "transparent")]),
                         "custom.cellOptions": {"type": "color-text"}}),
            ov("raft", {"mappings": vmap([(1, "RAFT LEADER", "purple"), (0, "follower", "text")]),
                        "custom.cellOptions": {"type": "color-text"}}),
            ov("postgres uptime", {"unit": "dtdurations"}),
        ],
        transformations=merge_organize(
            ["Time", "Value #A"],
            {"Value #B": "reachable", "Value #C": "write", "Value #D": "raft", "Value #E": "postgres uptime"},
            {"node": 0, "kind": 1, "state": 2, "Value #B": 3, "Value #C": 4, "Value #D": 5, "Value #E": 6}),
        sort=[{"displayName": "node"}]),
    table("Replication mesh (every node to every node)", 12, y, 12, 8, [
        tgt(f"max by (source, target, slot_state) ({s('pgd_demo_mesh_slot_info')})", "A", instant=True),
        tgt(f"max by (source, target) ({s('pgd_demo_mesh_slot_active')})", "B", instant=True),
        tgt(f"max by (source, target) ({s('pgd_demo_mesh_lag_bytes')})", "C", instant=True),
        tgt(f"max by (source, target) ({s('pgd_demo_mesh_lag_seconds')})", "D", instant=True),
        tgt(f"max by (source, target, status) ({s('pgd_demo_subscription_replicating')})", "E", instant=True)],
        "bdr.node_slots on each source (slot state, replay lag to target) and bdr.subscription_summary on each "
        "target (is it replicating from source).",
        overrides=[
            ov("slot", {"mappings": OK_REGEX("streaming"), "custom.cellOptions": {"type": "color-text"}}),
            ov("active", {"mappings": YES_NO, "custom.cellOptions": {"type": "color-text"}}),
            ov("subscription", {"mappings": OK_REGEX("replicating"), "custom.cellOptions": {"type": "color-text"}}),
            ov("lag bytes", {"unit": "bytes", "custom.cellOptions": {"type": "color-text"},
                             "color": {"mode": "thresholds"}, "thresholds": thresholds((None, "green"), (1, "orange"))}),
            ov("lag", {"unit": "s", "decimals": 3}),
        ],
        transformations=merge_organize(
            ["Time", "Value #A", "Value #E"],
            {"slot_state": "slot", "Value #B": "active", "Value #C": "lag bytes", "Value #D": "lag",
             "status": "subscription"},
            {"source": 0, "target": 1, "slot_state": 2, "Value #B": 3, "status": 4, "Value #C": 5, "Value #D": 6}),
        sort=[{"displayName": "source"}]),
]
y += 8


# ------------------------------------------------------------------ sequences (in the overview)
panels += [
    table("Sequence kinds", 0, y, 7, 8, [tgt(f"max by (table, sequence, kind) ({s('pgd_demo_sequence_kind')})", instant=True)],
          "bdr.sequences: galloc is globally unique (Raft hands each node its own id ranges); local is per node (the dangerous one).",
          overrides=[ov("kind", {"mappings": KIND_MAP, "custom.cellOptions": {"type": "color-text"}})],
          transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True, "Value": True},
                                                          "indexByName": {"table": 0, "sequence": 1, "kind": 2}}}],
          sort=[{"displayName": "table"}]),
    table("Per-node sequence state", 7, y, 17, 8, [
        tgt(f"max by (node, table, kind) ({s('pgd_demo_sequence_last_value')})", "A", instant=True),
        tgt(f"max by (node, table, kind) ({s('pgd_demo_table_max_id')})", "B", instant=True),
        tgt(f"max by (node, table, kind) ({s('pgd_demo_table_rows')})", "C", instant=True),
        tgt(f"max by (node, table, kind) ({s('pgd_demo_sequence_dup_risk')})", "D", instant=True)],
        "pg_sequences.last_value and max(id) read on each node directly. A LOCAL sequence whose last_value is "
        "below max(id) will re-issue existing ids if that node becomes leader. n/a = sequence not used yet on that node.",
        overrides=[
            ov("kind", {"mappings": KIND_MAP, "custom.cellOptions": {"type": "color-text"}}),
            ov("last_value on node", {"noValue": "n/a", "decimals": 0}),
            ov("max(id) on node", {"decimals": 0}),
            ov("rows", {"decimals": 0}),
            ov("if this node leads", {"mappings": vmap([(0, "ok", "green")]), "unit": "suffix: of next 1000 ids collide",
                                      "decimals": 0, "color": {"mode": "thresholds"},
                                      "thresholds": thresholds((None, "green"), (1, "red")),
                                      "custom.cellOptions": {"type": "color-background", "mode": "basic"}}),
        ],
        transformations=merge_organize(
            ["Time"],
            {"Value #A": "last_value on node", "Value #B": "max(id) on node", "Value #C": "rows",
             "Value #D": "if this node leads"},
            {"node": 0, "table": 1, "kind": 2, "Value #A": 3, "Value #B": 4, "Value #C": 5, "Value #D": 6}),
        sort=[{"displayName": "node"}]),
]
y += 8
panels += [
    timeseries("LOCAL sequence: how far each node's counter is behind max(id)", 0, y, 12, 8,
               [tgt(f"max by (node) ({LOCAL_MAX}) - on (node) "
                    f"max by (node) ({LOCAL_LAST})", legend="{{node}}")],
               "max(id) - last_value for each LOCAL sequence. Above 0, that node would re-issue existing ids "
               "(duplicate keys) if it became write leader. Repair or convert in the app to fix.",
               th=thresholds((None, "green"), (1, "red")),
               no_value="No LOCAL sequences: no node can re-issue existing ids"),
    table("galloc chunks held per node", 12, y, 12, 8, [
        tgt(f"max by (node, table, chunk) ({s('pgd_demo_galloc_chunk_start')})", "A", instant=True),
        tgt(f"max by (node, table, chunk) ({s('pgd_demo_galloc_chunk_end')})", "B", instant=True)],
        "bdr.galloc_chunk_info(): id ranges Raft has handed each node. Each node spends its own chunk, so ids jump "
        "after a leader change.",
        overrides=[ov("chunk_start", {"decimals": 0}), ov("chunk_end", {"decimals": 0})],
        transformations=merge_organize(["Time"], {"Value #A": "chunk_start", "Value #B": "chunk_end"},
                                       {"node": 0, "table": 1, "chunk": 2, "Value #A": 3, "Value #B": 4}),
        sort=[{"displayName": "node"}]),
]
y += 8

panels += [
    stat("Operator (PGDGroup)", 0, y, 6, 4,
         [tgt(f"max by (phase) ({s('pgd_demo_operator_ready')})", legend="{{phase}}", instant=True)],
         "PGDGroup status from the EDB PGD operator: phase, and whether its Ready condition is True.",
         {"mappings": vmap([(1, "Ready", "green"), (0, "Not ready", "red")]), "noValue": "not available",
          "color": {"mode": "thresholds"}, "thresholds": thresholds((None, "red"), (1, "green"))},
         text_mode="value_and_name"),
    stat("Nodes reachable", 6, y, 6, 4, [tgt(f"sum({s('pgd_demo_node_reachable')})", "A", "reachable", True),
                                         tgt(f"count({s('pgd_demo_node_reachable')})", "B", "total", True)],
         "Nodes the app could connect to directly (<node>-rw).", TEXT_STAT,
         text_mode="value_and_name", color_mode="value"),
    stat("Replication links", 12, y, 6, 4,
         [tgt(f"sum({s('pgd_demo_subscription_replicating')})", "A", "replicating", True),
          tgt(f"count({s('pgd_demo_subscription_replicating')})", "B", "total", True)],
         "Node-to-node subscriptions (bdr.subscription_summary on every node) that are enabled and replicating. "
         "A full mesh of n data nodes has n x (n-1).", TEXT_STAT, text_mode="value_and_name", color_mode="value"),
    stat("Worst replication lag (any link)", 18, y, 6, 4,
         [tgt(f"max({s('pgd_demo_mesh_lag_bytes')})", "A", "bytes", True),
          tgt(f"max({s('pgd_demo_mesh_lag_seconds')})", "B", "time", True)],
         "Highest replay lag over every source -> target slot in the mesh.",
         {"color": {"mode": "thresholds"}, "thresholds": thresholds((None, "green"), (1, "orange"))},
         text_mode="value_and_name", color_mode="value"),
]
for p_ in panels[-1:]:
    p_["fieldConfig"]["overrides"] = [
        {"matcher": {"id": "byFrameRefID", "options": "A"}, "properties": [{"id": "unit", "value": "bytes"}]},
        {"matcher": {"id": "byFrameRefID", "options": "B"}, "properties": [
            {"id": "unit", "value": "s"}, {"id": "decimals", "value": 3},
            {"id": "thresholds", "value": thresholds((None, "green"), (1, "orange"), (10, "red"))}]}]
y += 4
issues = table("Open issues", 0, y, 12, 7, [tgt(f"max by (issue) ({s('pgd_demo_health_issue')})", instant=True)],
               "Everything currently making PGD health WARNING or CRITICAL. Empty means healthy.",
               overrides=[ov("severity", {"mappings": ISSUE_MAP, "custom.width": 100,
                                          "custom.cellOptions": {"type": "color-background", "mode": "basic"}})],
               transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True},
                                                               "renameByName": {"Value": "severity"},
                                                               "indexByName": {"Value": 0, "issue": 1}}}],
               sort=[{"displayName": "severity", "desc": True}])
issues["fieldConfig"]["defaults"]["noValue"] = "No open issues: everything is healthy"
panels += [
    issues,
    table("PGD health checks", 12, y, 12, 7,
          [tgt(f"max by (check, node, message) ({s('pgd_demo_health_check')})", instant=True)],
          "PGD's own monitoring functions: monitor_group_raft and monitor_group_versions (group-wide), "
          "monitor_local_replslots (on each node).",
          overrides=[ov("status", {"mappings": CHECK_MAP, "custom.width": 100,
                                   "custom.cellOptions": {"type": "color-background", "mode": "basic"}}),
                     ov("check", {"custom.width": 100}), ov("node", {"custom.width": 130})],
          transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True},
                                                          "renameByName": {"Value": "status"},
                                                          "indexByName": {"Value": 0, "check": 1, "node": 2,
                                                                          "message": 3}}}],
          sort=[{"displayName": "check"}]),
]
y += 7
panels += [
    timeline("PGD health history", 0, y, 12, 6, [tgt(f"max({s('pgd_demo_overall_health')})", legend="PGD health")],
             HEALTH_MAP, "Overall PGD health over the time range."),
    timeseries("Replication lag, every link (bytes)", 12, y, 12, 6,
               [tgt(f"max by (source, target) ({s('pgd_demo_mesh_lag_bytes')})", legend="{{source}} -> {{target}}")],
               unit="bytes"),
]
y += 6

# ------------------------------------------------------------------ disk space and WAL retention
# PGD node PVCs are named <node>-<n>: map them to the node label and keep only this group's nodes.
NODES_OF_GROUP = f"group by (node) ({s('pgd_demo_node_info')})"


def pvc(metric, rng=""):
    m = f'{metric}{{namespace="$namespace"}}{rng}'
    return f'label_replace({m}, "node", "$1", "persistentvolumeclaim", "(.+)-[0-9]+")'


def per_node(expr):
    return f"max by (node) ({expr}) and on (node) {NODES_OF_GROUP}"


USED, CAP = "kubelet_volume_stats_used_bytes", "kubelet_volume_stats_capacity_bytes"
GROWTH = (f'label_replace(deriv({USED}{{namespace="$namespace"}}[6h]), '
                                 '"node", "$1", "persistentvolumeclaim", "(.+)-[0-9]+")')
SLOT_KIND = vmap([("peer", "peer", "green"), ("group", "group", "blue"), ("orphan", "ORPHAN", "red"),
                  ("other", "other", "purple")])
panels.append(row("Disk space and WAL retention", y))
y += 1
panels += [
    stat("Orphaned replication slots", 0, y, 5, 5, [tgt(f"sum({s('pgd_demo_node_orphan_slots')})", legend="orphaned", instant=True)],
         "PGD replication slots that belong to no PGD node (pg_replication_slots with no match in bdr.node_slots). "
         "Such a slot keeps every WAL file from its restart point until the volume fills: this is what stopped "
         "homelab-pgd-1 in Nov 2026. Anything above 0 needs looking at.",
         {"color": {"mode": "thresholds"}, "thresholds": thresholds((None, "green"), (1, "red")), "noValue": "n/a"}),
    panel("bargauge", "Volume used per node", 5, y, 10, 5,
          [tgt(per_node(f"{pvc(USED)} / {pvc(CAP)}"), legend="{{node}}", instant=True)],
          "Data volume (PGDATA incl. pg_wal) of each PGD node, from the kubelet. Alerts: 80% warning, 90% critical.",
          {"unit": "percentunit", "min": 0, "max": 1, "color": {"mode": "thresholds"},
           "thresholds": thresholds((None, "green"), (0.8, "orange"), (0.9, "red"))},
          options={"orientation": "horizontal", "displayMode": "gradient", "showUnfilled": True,
                   "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}),
    stat("Time until volume full", 15, y, 9, 5,
         [tgt(per_node(f"({pvc(CAP)} - {pvc(USED)}) / ({GROWTH} > 0)"),
              legend="{{node}}", instant=True)],
         "Free space divided by how fast the volume grew over the last 6 hours. Blank: not growing. "
         "Note that pg_wal grows ~190 MB/h even when idle while a slot holds it (archive_timeout = 5 min).",
         {"unit": "s", "noValue": "not growing", "color": {"mode": "thresholds"},
          "thresholds": thresholds((None, "red"), (86400, "orange"), (3 * 86400, "green"))},
         text_mode="value_and_name"),
]
y += 5
panels += [
    timeseries("Volume used per node", 0, y, 12, 7,
               [tgt(per_node(pvc(USED)), legend="{{node}}"),
                tgt(f"max({pvc(CAP)} and on (node) {NODES_OF_GROUP})", "B", "capacity")],
               "Used bytes on each PGD node's volume. A steady climb with no matching data growth is WAL being kept "
               "for a replication slot.", unit="bytes"),
    timeseries("WAL kept per replication slot", 12, y, 12, 7,
               [tgt(f"max by (node, kind, target) ({s('pgd_demo_node_slot_retained_bytes')})",
                    legend="{{node}}: {{kind}} -> {{target}}")],
               "pg_current_wal_lsn() - restart_lsn for every slot on every node: how much WAL each slot forces the node "
               "to keep. Healthy peer slots stay near zero; an orphaned slot, or a slot whose target node is down, climbs "
               "steadily.", unit="bytes"),
]
y += 7
slots_t = table("Replication slots on every node", 0, y, 15, 7,
                [tgt(f"max by (node, slot, kind, target, active, wal_status) ({s('pgd_demo_node_slot_retained_bytes')})",
                     instant=True)],
                "Every slot in pg_replication_slots on each node. kind: peer = slot for another PGD node, group = PGD's group "
                "slot, ORPHAN = bdr slot with no PGD node (should not exist), other = non-PGD slot.",
                overrides=[ov("kind", {"mappings": SLOT_KIND, "custom.width": 90,
                                       "custom.cellOptions": {"type": "color-background", "mode": "basic"}}),
                           ov("WAL kept", {"unit": "bytes", "custom.width": 100}),
                           ov("node", {"custom.width": 130}), ov("active", {"custom.width": 70})],
                transformations=[{"id": "organize", "options": {
                    "excludeByName": {"Time": True}, "renameByName": {"Value": "WAL kept"},
                    "indexByName": {"node": 0, "kind": 1, "target": 2, "active": 3, "wal_status": 4,
                                    "Value": 5, "slot": 6}}}],
                sort=[{"displayName": "WAL kept", "desc": True}])
alerts_t = table("Firing PGD alerts", 15, y, 9, 7,
                 [tgt('max by (alertname, severity, node) (ALERTS{alertstate="firing", namespace="$namespace", '
                      'alertname=~"PGD.*"})', instant=True)],
                 "Alerts from the pgd-demo PrometheusRule (orphaned slot, inactive slot keeping WAL, volume filling up, "
                 "node unreachable). They also show in the OKD console under Observe > Alerting.",
                 overrides=[ov("severity", {"mappings": vmap([("warning", "warning", "orange"),
                                                              ("critical", "critical", "red")]),
                                            "custom.width": 90,
                                            "custom.cellOptions": {"type": "color-background", "mode": "basic"}})],
                 transformations=[{"id": "organize", "options": {"excludeByName": {"Time": True, "Value": True},
                                                                 "indexByName": {"severity": 0, "alertname": 1,
                                                                                 "node": 2}}}],
                 sort=[{"displayName": "severity"}])
alerts_t["fieldConfig"]["defaults"]["noValue"] = "No PGD alerts firing"
panels += [slots_t, alerts_t]
y += 7

# ------------------------------------------------------------------ section 2
panels.append(row("2. Leader history and replication lag from the write leader", y))
y += 1
panels += [
    stat("Raft elections (time range)", 0, y, 6, 3,
         [tgt(f"max by (scope) (changes({s('pgd_demo_raft_term')}[$__range]))", legend="{{scope}}", instant=True)],
         "Raft term changes over the dashboard's time range. Each one is a Raft leader election.",
         {"color": {"mode": "thresholds"}, "thresholds": thresholds((None, "green"), (1, "orange"))},
         text_mode="value_and_name"),
    stat("Nodes ACTIVE", 6, y, 5, 3, [tgt(f"sum({s('pgd_demo_node_active')})", "A", "active", True),
                                      tgt(f"count({s('pgd_demo_node_active')})", "B", "total", True)],
         "Nodes whose peer_state_name is ACTIVE, out of all nodes in the group.",
         TEXT_STAT, text_mode="value_and_name", color_mode="value"),
    stat("Max replay lag from leader (bytes)", 11, y, 5, 3, [tgt(f"max({s('pgd_demo_replay_lag_bytes')})", instant=True)],
         "Worst replay_lag_bytes from the leader to any node. 0 = every node has applied everything the leader committed.",
         {"unit": "bytes", "color": {"mode": "thresholds"}, "thresholds": thresholds((None, "green"), (1, "orange"))}),
    stat("Max replay lag from leader (time)", 16, y, 4, 3, [tgt(f"max({s('pgd_demo_replay_lag_seconds')})", instant=True)],
         "Worst replay_lag from the leader to any node.",
         {"unit": "s", "decimals": 3, "color": {"mode": "thresholds"},
          "thresholds": thresholds((None, "green"), (1, "orange"), (10, "red"))}),
    stat("Collector errors", 20, y, 4, 3,
         [tgt(f"max({s('pgd_demo_state_errors')}) + max({s('pgd_demo_health_collect_errors')})", instant=True)],
         "Errors the demo app hit while collecting state (router or a node unreachable). Details are in the app's event log.",
         {"noValue": "app down", "color": {"mode": "thresholds"},
          "thresholds": thresholds((None, "green"), (1, "red"))}),
]
y += 3
panels += [
    timeline("Write leader over time", 0, y, 12, 6,
             [tgt(f"max by (node) ({s('pgd_demo_write_leader')})", legend="{{node}}")],
             vmap([(1, "WRITE LEADER", "blue"), (0, "follower", "#2a2f3a")]),
             "When each node held the write lead. Switchovers and failovers show up as hand-offs."),
    timeline("Raft leader over time (data group)", 12, y, 12, 6,
             [tgt(f"max by (node) ({RAFT_LEADER})", legend="{{node}}")],
             vmap([(1, "RAFT LEADER", "purple"), (0, "follower", "#2a2f3a")]),
             "When each node led the data group's Raft consensus."),
]
y += 6
panels += [
    timeseries("Replay lag from the write leader (bytes)", 0, y, 12, 8,
               [tgt(f"max by (node) ({s('pgd_demo_replay_lag_bytes')})", legend="{{node}}")], unit="bytes"),
    timeseries("Replay lag from the write leader (time)", 12, y, 12, 8,
               [tgt(f"max by (node) ({s('pgd_demo_replay_lag_seconds')})", legend="{{node}}")], unit="s"),
]
y += 8

# ------------------------------------------------------------------ section 4
panels.append(row("3. Is it safe to move the write leader or a Raft leader?", y))
y += 1
panels += [
    stat("Verdict for every node", 0, y, 10, 5,
         [tgt(f"max by (target) ({s('pgd_demo_switch_verdict')})", legend="{{target}}", instant=True)],
         "The app's safety check, evaluated for every possible target on each scrape. Click a node to open the "
         "checked switchover page for it.",
         {"mappings": VERDICT_MAP, "color": {"mode": "thresholds"}, "thresholds": thresholds((None, "text")),
          "links": [{"title": "Run safety checks & move the write leader to ${__field.labels.target}",
                     "url": "${app_url}/switch?target=${__field.labels.target}", "targetBlank": True}]},
         text_mode="value_and_name"),
    stat("Move leader to $target", 10, y, 7, 5,
         [tgt(f"max({VERDICT_T})", instant=True)],
         "Verdict for the node picked in the 'Move leader to' dropdown. WAIT means only lag is outstanding: "
         "a STRICT switchover will wait for it to drain. Click to open the checked switchover page.",
         {"mappings": VERDICT_MAP, "noValue": "pick a target", "color": {"mode": "thresholds"},
          "thresholds": thresholds((None, "text")),
          "links": [{"title": "Run safety checks & move the write leader to ${target}",
                     "url": "${app_url}/switch?target=${target}", "targetBlank": True}]}),
    {"type": "text", "id": nid(), "title": "Move a leader", "gridPos": {"x": 17, "y": y, "w": 7, "h": 5},
     "description": "Grafana dashboards are read-only, so the switchover itself runs in the lab app.",
     "options": {"mode": "markdown", "content":
         "### [Run safety checks & move leader to ${target} \u2192](${app_url}/switch?target=${target})\n\n"
         "[Move a Raft leader instead \u2192](${app_url}/switch?kind=raft-data)\n\n"
         "Opens the lab's switchover page. It re-runs the checks, explains each one, and only allows what the "
         "verdict allows: **SAFE** strict or fast, **WAIT** strict only, **UNSAFE** blocked. "
         "The app also refuses unsafe requests itself."}},
]
y += 5
panels += [
    table("Checks for $target", 0, y, 14, 9,
          [tgt(f"max by (check_id, check, severity) ({CHECK_T})",
               instant=True)],
          "Same checks as the app's safety check. For the detailed explanation of a failure, run the check in the app.",
          overrides=[
              ov("result", {"mappings": vmap([(0, "PASS", "green"), (1, "WAIT", "orange"), (2, "FAIL", "red")]),
                            "custom.cellOptions": {"type": "color-background", "mode": "basic"},
                            "custom.width": 80}),
              ov("severity", {"custom.width": 80}),
          ],
          transformations=[
              {"id": "sortBy", "options": {"fields": {}, "sort": [{"field": "check_id"}]}},
              {"id": "organize", "options": {"excludeByName": {"Time": True, "check_id": True},
                                             "renameByName": {"Value": "result"},
                                             "indexByName": {"Value": 0, "check": 1, "severity": 2}}}]),
    timeline("Verdict history", 14, y, 10, 9,
             [tgt(f"max by (target) ({s('pgd_demo_switch_verdict')})", legend="{{target}}")], VERDICT_MAP,
             "When it would have been safe to move the leader to each node."),
]
y += 9
RAFT_VERDICT_MAP = vmap([(-1, "current Raft leader", "purple"), (0, "SAFE", "green"), (2, "UNSAFE", "red")])
panels += [
    stat("Move the Raft leader: verdict per node", 0, y, 24, 5,
         [tgt(f"max by (scope, kind, target) ({s('pgd_demo_raft_switch_verdict')})", legend="{{scope}} \u2192 {{target}}",
              instant=True)],
         "Raft safety check for every member of the data group and the parent group: target is a Raft member, "
         "ACTIVE, reachable, caught up with the leader's Raft log, Raft has a healthy majority and the group is "
         "stable (PGDGroup Ready, no node joining or parting). Moving the Raft leader does not move the write leader. "
         "Click a tile to open the checked transfer page.",
         {"mappings": RAFT_VERDICT_MAP, "color": {"mode": "thresholds"}, "thresholds": thresholds((None, "text")),
          "links": [{"title": "Run safety checks & move the Raft leader to ${__field.labels.target}",
                     "url": "${app_url}/switch?kind=${__field.labels.kind}&target=${__field.labels.target}",
                     "targetBlank": True}]},
         text_mode="value_and_name"),
]
y += 5

# ------------------------------------------------------------------ versions (bottom)
panels.append(row("Versions", y))
y += 1
VERSION_STATUS = vmap([(0, "newest", "green")]) + [
    {"type": "range", "options": {"from": -1e15, "to": -0.5, "result": {"text": "behind", "color": "orange", "index": 1}}}]


def behind(num_metric):
    """0 if the node runs the newest version in the cluster, negative if it is behind."""
    return f"max by (node) ({s(num_metric)}) - on () group_left max({s(num_metric)})"


panels += [
    table("Versions", 0, y, 24, 6, [
        tgt(f"max by (node, pg_version, pgd_version) ({s('pgd_demo_node_version_info')})", "A", instant=True),
        tgt(behind("pgd_demo_node_pg_version_num"), "B", instant=True),
        tgt(behind("pgd_demo_node_pgd_version_num"), "C", instant=True)],
        "server_version and bdr.bdr_version(), read on each node directly. Status compares each node with the newest "
        "version in the cluster: 'behind' means that node hasn't been upgraded yet (e.g. mid rolling upgrade).",
        overrides=[ov(col, {"mappings": VERSION_STATUS, "custom.cellOptions": {"type": "color-background", "mode": "basic"},
                            "custom.width": 120})
                   for col in ("postgres status", "pgd status")],
        transformations=merge_organize(
            ["Time", "Value #A"],
            {"pg_version": "postgres", "Value #B": "postgres status", "pgd_version": "pgd", "Value #C": "pgd status"},
            {"node": 0, "pg_version": 1, "Value #B": 2, "pgd_version": 3, "Value #C": 4}),
        sort=[{"displayName": "node"}]),
]
y += 6

dashboard = {
    "uid": "pgd-write-leader-lab",
    "title": "PGD write-leader lab",
    "description": "Sections 2-4 of the pgd-demo app (nodes, write/Raft leaders and lag, sequences, switchover "
                   "safety), from its /metrics endpoint. Works for any cluster/group the app runs against.",
    "tags": ["pgd", "postgres"],
    "editable": True,
    "schemaVersion": 39,
    "time": {"from": "now-1h", "to": "now"},
    "refresh": "30s",
    "timezone": "browser",
    "graphTooltip": 1,
    "links": [{"title": "Open the PGD write-leader lab app (actions)", "type": "link", "url": "${app_url}",
               "targetBlank": True, "icon": "external link"},
              {"title": "pgAdmin", "type": "link", "url": "${pgadmin_url}", "targetBlank": True,
               "icon": "external link", "tooltip": "Open pgAdmin"}],
    "templating": {"list": [
        {"name": "datasource", "label": "Prometheus", "type": "datasource", "query": "prometheus",
         "regex": "", "current": {}, "options": [], "refresh": 1, "hide": 0},
        query_var("cluster", "Cluster", "label_values(pgd_demo_info, cluster)"),
        query_var("group", "PGD group", 'label_values(pgd_demo_info{cluster="$cluster"}, group)'),
        query_var("target", "Move leader to",
                  f"query_result(max by (target) ({s('pgd_demo_switch_verdict')} >= 0))", regex='/target="([^"]+)"/'),
        query_var("namespace", "Namespace", f"label_values({s('pgd_demo_info')}, namespace)", hide=2),
        query_var("app_url", "App URL", f"label_values({s('pgd_demo_info')}, app_url)", hide=2),
        query_var("pgadmin_url", "pgAdmin URL", f"label_values({s('pgd_demo_info')}, pgadmin_url)", hide=2),
    ]},
    "annotations": {"list": []},
    "panels": panels,
}

dash_json = json.dumps(dashboard, indent=2)
cr = """# GENERATED by tools/gen_dashboard.py - edit the script, not this file.
# One dashboard for every cluster: pick datasource / cluster / PGD group at the top.
apiVersion: grafana.integreatly.org/v1beta1
kind: GrafanaDashboard
metadata:
  name: pgd-write-leader-lab
  labels:
    app: pgd-demo
spec:
  # The overlay sets the Grafana instance to target.
  instanceSelector:
    matchLabels:
      dashboards: grafana
  folder: PGD
  resyncPeriod: 10m
  json: |
""" + "\n".join("    " + line for line in dash_json.splitlines()) + "\n"
with open(OUT, "w") as f:
    f.write(cr)
print(f"{len(panels)} panels written to {os.path.relpath(OUT)}")
