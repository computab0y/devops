# pgd-demo: PGD write-leader lab + Grafana dashboard

A small Flask app that writes through the PGD router (Connection Manager in 6.x, PGD
Proxy in 5.x) and shows what happens to sequences and duplicate keys when the write
leader moves. It also exposes its view as Prometheus metrics. A Grafana dashboard,
**PGD write-leader lab**, shows the app's sections 2–4 for any cluster it runs on:

| Dashboard row | Source |
|---|---|
| Overview: health, replication, leaders, sequences | an overall verdict plus open issues, built from PGD's monitoring functions (`bdr.monitor_group_raft()`, `bdr.monitor_group_versions()`, `bdr.monitor_local_replslots()` on every node), node reachability, the full replication mesh (`bdr.node_slots` and `bdr.subscription_summary` on every node), and the EDB operator's PGDGroup phase. Also shows the write and Raft leaders and the sequences (below). |
| 2. Nodes and replication lag from the write leader | `bdr.node_summary`, `bdr.node_group_routing_summary` (write leader), `bdr.group_raft_details` (Raft leaders of the data group and its parent), `bdr.node_slots` on the write leader |
| Sequences (in the overview) | `bdr.sequences`, plus `pg_sequences.last_value`, `max(id)` and `bdr.galloc_chunk_info()` read on every node |
| Disk space and WAL retention | volume usage from the kubelet, every replication slot on every node, firing PGD alerts |
| 3. Is it safe to move the write leader or a Raft leader? | the app's safety checks, evaluated for every possible target on each scrape |
| Versions (bottom) | Postgres / PGD version per node, flagged when a node is behind the newest |

Nothing in the dashboard is tied to one cluster. Nodes, the write leader and Raft
leaders are discovered on every scrape. Datasource, **Cluster** and **PGD group** are
dropdowns, so one dashboard covers every cluster/group the app runs against.
Actions stay in the app, which the dashboard links to: switchover, repair, convert, and moving a Raft leader.
Moving a leader always goes through a safety check. The checked page `/switch` handles the write leader
(`?kind=write`) and the Raft leader of the data group or parent group (`?kind=raft-data|raft-parent`).
The API refuses UNSAFE moves itself, unless the request sets `force`, which the lab uses to demonstrate a bad switchover.

A Raft leader move is SAFE only when all of these pass: the Raft group exists; the target is not already
the leader, is a Raft member, is ACTIVE and is reachable; Raft has a majority (`bdr.monitor_group_raft`);
the group is stable (PGDGroup Ready and no node joining, parting or down); and the target has caught up
with the leader's Raft log (`match_index` from `bdr.get_raft_status(group, true)` on the leader, at most
`RAFT_MAX_LAG_ENTRIES`, default 50, behind). If the operator status can't be read, the stability check
falls back to the PGD node states.

The app sits behind an **OKD / OpenShift login** (an oauth-proxy sidecar on the Route). Only users who may
`update` the PGDGroup in the app's namespace get in. Their username is recorded in the app's event log
for every switchover. Prometheus scrapes `:8080/metrics` directly, without the login.

```
base/                 app: Deployment, Service, ServiceMonitor, Route, RBAC; app/app.py + app/index.html
dashboard/            GrafanaDashboard (generated - see tools/)
overlay/<cluster>/
  app/                namespace + PGD group + cluster name + secret for that cluster
  dashboard/          namespace + instanceSelector of that cluster's Grafana
tools/gen_dashboard.py    regenerates dashboard/grafana-dashboard.yaml
tools/check_dashboard.py  runs every dashboard query against Prometheus and reports empty ones
```

The app runs as ServiceAccount `pgd-demo`, which may only `get` PGDGroups in its own
namespace (`base/rbac.yaml`). That permission is used for the operator status panel.
Without it, the panel just shows "not available".

## Deploy

```bash
oc apply -k operators/subscription/pgd-demo/overlay/homelab
```

Editing `base/app/app.py` or `index.html` changes the generated ConfigMap's name hash,
so the pod rolls by itself on the next apply.

## Add another cluster

Requirements: a PGDGroup from the EDB PGD operator, the Prometheus Operator (OpenShift
user-workload monitoring works as is), and Grafana Operator v5 with a Prometheus
datasource that can see the scraped metrics.

1. `cp -r overlay/homelab overlay/<cluster>`
2. In `overlay/<cluster>/app/kustomization.yaml`, set the values below. Everything else
   follows the EDB operator's naming, derived from the PGDGroup name `<g>`:

   | Field | Value |
   |---|---|
   | `namespace` | namespace of the PGDGroup |
   | `CLUSTER_NAME` | any short name; becomes the dashboard's Cluster value |
   | `PGD_GROUP` | `<g>` |
   | `ROUTER_HOST` | `<g>-proxy` |
   | `APP_URL` | the app's route URL (optional; feeds the dashboard link) |
   | `PGADMIN_URL` | pgAdmin's URL (optional; feeds the dashboard's pgAdmin link) |
   | secret patch | `<g>-app` |

   Nodes are reached as `<node>-rw` (`NODE_HOST_FMT` in `base/kustomization.yaml`).
3. In `overlay/<cluster>/dashboard/kustomization.yaml`, set the Grafana namespace and
   instanceSelector labels. If several clusters share one Grafana, deploy the dashboard
   once and only deploy `app/` on the others.
4. Create the login cookie secret (once per namespace, not stored in git):
   `oc create secret generic pgd-demo-oauth-proxy -n <namespace> --from-literal=session_secret="$(openssl rand -base64 24)"`
5. `oc apply -k overlay/<cluster>`
6. After a minute of scrapes, check every panel has data:
   `python3 tools/check_dashboard.py --cluster <CLUSTER_NAME> --group <g>`.
   Panels that are legitimately empty, such as "Open issues" when all is healthy, are marked `ok*`.

Not OpenShift? Replace `base/route.yaml` with an Ingress in the overlay. If your
Prometheus only selects labelled ServiceMonitors, add that label in the overlay.

**Several PGD data groups** (e.g. one per location): deploy the app once per group, with
a `nameSuffix` and a different `PGD_GROUP`/`ROUTER_HOST`. Each group then shows up in
the PGD group dropdown.

## Alerts

`base/prometheusrule.yaml` (evaluated by user-workload monitoring; shown in the OKD console under
Observe > Alerting and in the dashboard's "Firing PGD alerts" table):

| Alert | Fires when |
|---|---|
| `PGDOrphanedReplicationSlot` | a node has a bdr slot for no PGD node, for 10 min |
| `PGDInactiveSlotRetainingWAL` | an inactive slot keeps more than 2 GiB of WAL, for 15 min |
| `PGDNodeUnreachable` | the app cannot connect to a node, for 5 min (critical) |
| `PGDVolumeFillingUp` | a node's volume is over 80% (warning) / 90% (critical) |
| `PGDVolumeFullWithin24h` | at the last 6 h's growth rate the volume fills within 24 h (and is over 40%) |

Why: in Nov 2026 an orphaned slot on homelab-pgd-1 kept all WAL (about 190 MB/h even when idle,
because `archive_timeout` is 5 min) until the 15 Gi volume filled and Postgres refused to start;
the other nodes then kept WAL for the dead node. The fix was deleting the node's Cluster
(`oc delete cluster.postgresql.k8s.enterprisedb.io <node>`): the operator parts it and joins a
replacement. To clear a confirmed orphan instead: `SELECT pg_drop_replication_slot('<slot>')` on that node.

## Change the dashboard

Edit `tools/gen_dashboard.py`, run `python3 tools/gen_dashboard.py`, and apply.
The operator re-applies the CR every 10 minutes, so edits made in the Grafana UI are
overwritten. Save them back into the script.

## Metrics

All metrics carry `cluster` and `group` labels.

| Metric | Labels |
|---|---|
| `pgd_demo_info` | `pgd_version`, `app_url` |
| `pgd_demo_overall_health` | none; values: 0 HEALTHY, 1 WARNING, 2 CRITICAL |
| `pgd_demo_health_issue` | `issue`; value is the severity |
| `pgd_demo_health_check` | `check`, `node`, `message`; values: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN |
| `pgd_demo_operator_ready` | `phase`, `message` |
| `pgd_demo_node_reachable` | `node` |
| `pgd_demo_node_version_info` | `node`, `pg_version`, `pgd_version` |
| `pgd_demo_node_pg_version_num`, `pgd_demo_node_pgd_version_num`, `pgd_demo_node_start_time_seconds` | `node` |
| `pgd_demo_mesh_slot_active`, `pgd_demo_mesh_lag_bytes`, `pgd_demo_mesh_lag_seconds` | `source`, `target` |
| `pgd_demo_node_slot_retained_bytes` (WAL each slot makes the node keep; every slot in `pg_replication_slots`) | `node`, `slot`, `kind` (peer / group / orphan / other), `target`, `active`, `wal_status` |
| `pgd_demo_node_orphan_slots` (bdr slots that belong to no PGD node) | `node` |
| `pgd_demo_mesh_slot_info` | `source`, `target`, `slot_state` |
| `pgd_demo_subscription_replicating` | `source`, `target`, `status` |
| `pgd_demo_health_collect_errors` | none |
| `pgd_demo_write_leader` | `node` |
| `pgd_demo_raft_leader` | `raft_group`, `scope`, `node` |
| `pgd_demo_raft_term` | `raft_group`, `scope` |
| `pgd_demo_raft_node_state` | `raft_group`, `node`, `state` |
| `pgd_demo_raft_ok` | none |
| `pgd_demo_node_info` | `node`, `kind`, `state` |
| `pgd_demo_node_active` | `node` |
| `pgd_demo_replay_lag_bytes` | `node` |
| `pgd_demo_replay_lag_seconds` | `node` |
| `pgd_demo_slot_info` | `node`, `slot_state` |
| `pgd_demo_sequence_kind` | `table`, `sequence`, `kind` |
| `pgd_demo_sequence_last_value`, `pgd_demo_table_max_id`, `pgd_demo_table_rows`, `pgd_demo_sequence_dup_risk` | `node`, `table`, `kind` |
| `pgd_demo_galloc_chunk_start`, `pgd_demo_galloc_chunk_end` | `node`, `table`, `chunk` |
| `pgd_demo_switch_verdict` | `target`; values: -1 leader, 0 SAFE, 1 WAIT, 2 UNSAFE |
| `pgd_demo_raft_switch_verdict` | `scope`, `kind`, `raft_group`, `target`; values: -1 Raft leader, 0 SAFE, 2 UNSAFE |
| `pgd_demo_switch_check_status` | `target`, `check_id`, `check`, `severity`; values: 0 PASS, 1 WAIT, 2 FAIL |
| `pgd_demo_state_errors` | none |
| `pgd_demo_node_query_ok` | `node` |
| `pgd_demo_metrics_duration_seconds` | none |

The app needs the `<g>-app` user (a member of `bdr_superuser`) and creates the
`demo_galloc` and `demo_local` tables in database `app`.
