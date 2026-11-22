"""PGD write-leader / sequence / duplicate-key demo.

Runs a background writer through the PGD router (Connection Manager in 6.x,
PGD Proxy in 5.x) and exposes a small dashboard + JSON API that shows:
  * the current write leader and every leader change the writer sees
  * sequence kinds, per-node sequence state and galloc chunks
  * replication lag from the write leader to every other node
  * a "is it safe to move the write leader to node X?" check
  * actions: switchover (strict/fast), repair/convert a sequence, reset demo
"""
import os
import threading
import time
import datetime
import collections
import json
import ssl
import traceback
import urllib.request

import psycopg2
import psycopg2.extras
from flask import Flask, jsonify, request, Response

ROUTER_HOST = os.environ.get("ROUTER_HOST", "homelab-pgd-proxy")
ROUTER_PORT = int(os.environ.get("ROUTER_PORT", "5432"))
NODE_HOST_FMT = os.environ.get("NODE_HOST_FMT", "{node}-rw")
DB = os.environ.get("PGDATABASE", "app")
USER = os.environ.get("PGUSER", "postgres")
PASSWORD = os.environ.get("PGPASSWORD", "")
SSLMODE = os.environ.get("PGSSLMODE", "require")
GROUP = os.environ.get("PGD_GROUP", "homelab-pgd")
WRITE_INTERVAL = float(os.environ.get("WRITE_INTERVAL", "0.5"))
# an inactive slot keeping at least this much WAL counts as a WARNING health issue
SLOT_WARN_GIB = float(os.environ.get("SLOT_WARN_GIB", "2"))
# Labels every metric so one Grafana dashboard can tell clusters/groups apart.
CLUSTER = os.environ.get("CLUSTER_NAME", "default")
APP_URL = os.environ.get("APP_URL", "")
PGADMIN_URL = os.environ.get("PGADMIN_URL", "")  # optional: shown as a dashboard link

TABLES = {
    # table: (sequence, kind we want at setup, description)
    "demo_galloc":    ("demo_galloc_id_seq",    "galloc",      "int key, galloc chunks handed out by Raft"),
    "demo_local":     ("demo_local_id_seq",     "local",       "bigint key, LOCAL sequence (the dangerous one)"),
}

app = Flask(__name__)
events = collections.deque(maxlen=300)
leader_changes = collections.deque(maxlen=50)
stats = {t: {"ok": 0, "dup_key": 0, "other_err": 0, "last_id": None} for t in TABLES}
writer_state = {"connected_node": None, "paused": False, "last_error": None, "started": None}
lock = threading.Lock()


def now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%H:%M:%S.%f")[:-3]


def who():
    """OKD user the oauth-proxy sidecar logged in (X-Forwarded-User), for the event log."""
    try:
        return request.headers.get("X-Forwarded-User") or "anonymous"
    except RuntimeError:  # outside a request
        return "system"


def log(kind, msg, **extra):
    with lock:
        events.appendleft({"t": now(), "kind": kind, "msg": msg, **extra})


def connect(host, port=5432, autocommit=True, timeout=3):
    c = psycopg2.connect(host=host, port=port, dbname=DB, user=USER, password=PASSWORD,
                         sslmode=SSLMODE, connect_timeout=timeout,
                         application_name="pgd-demo")
    c.autocommit = autocommit
    return c


def q(conn, sql, args=None):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, args)
        if cur.description:
            return [dict(r) for r in cur.fetchall()]
        return []


def router():
    return connect(ROUTER_HOST, ROUTER_PORT)


def node_conn(node):
    return connect(NODE_HOST_FMT.format(node=node))


# --------------------------------------------------------------------------- setup
def setup_schema():
    """Create demo tables. Safe to run repeatedly."""
    c = router()
    try:
        for table, (seq, kind, _) in TABLES.items():
            exists = q(c, "SELECT to_regclass(%s) AS r", (table,))[0]["r"]
            if exists:
                continue
            coltype = "integer" if kind == "galloc" else "bigint"
            q(c, f"CREATE SEQUENCE IF NOT EXISTS {seq} AS {coltype}")
            q(c, "SELECT bdr.alter_sequence_set_kind(%s::regclass, %s)", (seq, kind))
            q(c, f"""CREATE TABLE {table} (
                        id {coltype} PRIMARY KEY DEFAULT nextval('{seq}'),
                        written_on text NOT NULL,
                        note text,
                        created_at timestamptz NOT NULL DEFAULT clock_timestamp())""")
            q(c, f"ALTER SEQUENCE {seq} OWNED BY {table}.id")
            log("setup", f"created {table} with {kind} sequence {seq}")
    finally:
        c.close()


# --------------------------------------------------------------------------- writer
def writer_loop():
    writer_state["started"] = now()
    conn = None
    while True:
        if writer_state["paused"]:
            time.sleep(0.5)
            continue
        try:
            if conn is None or conn.closed:
                conn = router()
                node = q(conn, "SELECT node_name FROM bdr.local_node_summary")[0]["node_name"]
                prev = writer_state["connected_node"]
                writer_state["connected_node"] = node
                if prev != node:
                    leader_changes.appendleft({"t": now(), "from": prev, "to": node})
                    log("leader", f"writer now connected to write leader {node} (was {prev})")
            for table in TABLES:
                try:
                    r = q(conn, f"INSERT INTO {table}(written_on, note) "
                                f"SELECT node_name, 'demo' FROM bdr.local_node_summary RETURNING id, written_on")
                    stats[table]["ok"] += 1
                    stats[table]["last_id"] = r[0]["id"]
                except psycopg2.errors.UniqueViolation as e:
                    stats[table]["dup_key"] += 1
                    log("dup", f"{table}: DUPLICATE KEY on {writer_state['connected_node']}: "
                               f"{str(e).splitlines()[0]} {str(e).splitlines()[1] if len(str(e).splitlines())>1 else ''}",
                        table=table)
                except (psycopg2.OperationalError, psycopg2.InterfaceError):
                    raise
                except Exception as e:  # noqa
                    stats[table]["other_err"] += 1
                    log("error", f"{table}: {str(e).splitlines()[0]}", table=table)
            writer_state["last_error"] = None
        except Exception as e:  # connection-level failure: leader change / node down
            writer_state["last_error"] = str(e).splitlines()[0] if str(e) else repr(e)
            log("conn", f"connection lost/refused: {writer_state['last_error']} - reconnecting")
            try:
                if conn:
                    conn.close()
            except Exception:
                pass
            conn = None
            time.sleep(1)
            continue
        time.sleep(WRITE_INTERVAL)


# --------------------------------------------------------------------------- state
def cluster_state():
    st = {"errors": []}
    try:
        c = router()
    except Exception as e:
        return {"errors": [f"router unreachable: {e}"]}
    try:
        st["routing"] = q(c, "SELECT node_group_name, write_lead FROM bdr.node_group_routing_summary")
        st["raft"] = q(c, "SELECT * FROM bdr.monitor_group_raft(%s)", (GROUP,))
        try:
            st["pgd_version"] = q(c, "SELECT bdr.bdr_version() AS v")[0]["v"]
        except Exception:
            st["pgd_version"] = "unknown"
        try:
            # one row per (raft group, member): covers the data group and its parent group
            st["raft_details"] = q(c, """SELECT node_name, node_group_name, state, leader_name, current_term
                                         FROM bdr.group_raft_details
                                         ORDER BY node_group_name, node_name""")
        except Exception as e:
            st["raft_details"] = []
            st["errors"].append(f"raft details: {str(e).splitlines()[0]}")
        st["nodes"] = q(c, """SELECT node_name, node_group_name, peer_state_name,
                                     COALESCE(node_kind_name, '') AS node_kind
                              FROM bdr.node_summary ORDER BY node_name""")
        st["sequences"] = q(c, """SELECT relname AS seq, seqkind
                                  FROM bdr.sequences
                                  WHERE nspname = 'public' AND relname LIKE 'demo_%%'
                                  ORDER BY 1""")
        try:
            st["conflicts"] = q(c, """SELECT h.local_time::text AS local_time, h.relname, h.conflict_type,
                                             h.conflict_resolution,
                                             COALESCE(n.node_name, h.origin_node_id::text) AS origin_node_name,
                                             (SELECT node_name FROM bdr.local_node_summary) AS target_node_name
                                      FROM bdr.conflict_history_summary h
                                      LEFT JOIN bdr.node_summary n ON n.node_id = h.origin_node_id
                                      ORDER BY h.local_time DESC LIMIT 10""")
        except Exception as e:
            st["conflicts"] = []
            st["errors"].append(f"conflict history: {str(e).splitlines()[0]}")
    except Exception as e:
        st["errors"].append(str(e).splitlines()[0])
    finally:
        c.close()

    leader = None
    for r in st.get("routing", []):
        if r["node_group_name"] == GROUP:
            leader = r["write_lead"]
    st["leader"] = leader
    st["group"] = GROUP
    raft_leaders = {}
    for r in st.get("raft_details", []):
        g = r["node_group_name"]
        if r["state"] == "RAFT_LEADER":
            raft_leaders[g] = r["node_name"]
        elif r.get("leader_name"):
            raft_leaders.setdefault(g, r["leader_name"])
    st["raft_leaders"] = raft_leaders
    data_nodes = [n["node_name"] for n in st.get("nodes", [])
                  if n["node_group_name"] == GROUP and n["node_kind"] != "witness"]
    st["data_nodes"] = data_nodes

    # lag as seen from the write leader
    st["lag"] = []
    if leader:
        try:
            lc = node_conn(leader)
            st["lag"] = q(lc, """SELECT target_name, state, replay_lag_bytes,
                                        replay_lag::text AS replay_lag,
                                        EXTRACT(EPOCH FROM replay_lag)::float8 AS replay_lag_seconds
                                 FROM bdr.node_slots WHERE target_name IS NOT NULL ORDER BY target_name""")
            lc.close()
        except Exception as e:
            st["errors"].append(f"lag from {leader}: {str(e).splitlines()[0]}")

    # per node sequence view
    st["per_node"] = {}
    for n in data_nodes:
        info = {}
        try:
            nc = node_conn(n)
            for table, (seq, _, _) in TABLES.items():
                row = q(nc, f"""WITH s AS (SELECT COALESCE(last_value, 0) + 1 AS nxt FROM pg_sequences
                                               WHERE sequencename = %s)
                                SELECT (SELECT last_value FROM pg_sequences
                                         WHERE sequencename = %s) AS seq_last_value,
                                        (SELECT max(id) FROM {table}) AS table_max_id,
                                        (SELECT count(*) FROM {table}) AS rows,
                                        (SELECT count(*) FROM {table}, s
                                          WHERE id BETWEEN s.nxt AND s.nxt + 999) AS taken_next_1000""", (seq, seq))[0]
                kind = next((s["seqkind"] for s in st.get("sequences", []) if s["seq"] == seq), None)
                if kind == "galloc":
                    try:
                        row["chunks"] = q(nc, "SELECT * FROM bdr.galloc_chunk_info(%s::regclass)", (seq,))
                    except Exception as e:
                        row["chunks"] = [{"error": str(e).splitlines()[0]}]
                info[table] = row
            nc.close()
        except Exception as e:
            info["error"] = str(e).splitlines()[0]
        st["per_node"][n] = info
    return st


# --------------------------------------------------------------------------- health (metrics only)
HEALTH_CODE = {"OK": 0, "WARNING": 1, "CRITICAL": 2}
SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount"


def _health(v):
    """PGD monitor status -> 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN."""
    return HEALTH_CODE.get(str(v or "").upper(), 3)


def operator_status():
    """PGDGroup status from the EDB PGD operator. Needs 'get pgdgroups' (base/rbac.yaml)."""
    ns = open(f"{SA_DIR}/namespace").read().strip()
    token = open(f"{SA_DIR}/token").read().strip()
    ctx = ssl.create_default_context(cafile=f"{SA_DIR}/ca.crt")
    url = f"https://kubernetes.default.svc/apis/pgd.k8s.enterprisedb.io/v1beta1/namespaces/{ns}/pgdgroups/{GROUP}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, context=ctx, timeout=3) as r:
        status = json.load(r).get("status", {})
    ready = next((c for c in status.get("conditions", []) if c.get("type") == "Ready"), {})
    return {"phase": status.get("phase", ""), "ready": ready.get("status") == "True",
            "message": ready.get("message", "")}


def health_state(st):
    """PGD health checks, versions and the full replication mesh, read from every node."""
    h = {"checks": [], "nodes": {}, "errors": [], "operator": None}
    raft = (st.get("raft") or [None])[0]
    if raft:
        h["checks"].append({"check": "raft", "node": "group", "status": raft.get("status"),
                            "message": raft.get("message")})
    try:
        c = router()
        try:
            r = q(c, "SELECT status, message FROM bdr.monitor_group_versions()")[0]
            h["checks"].append({"check": "versions", "node": "group", **r})
        finally:
            c.close()
    except Exception as e:
        h["errors"].append(f"group checks: {str(e).splitlines()[0]}")

    for n in [x["node_name"] for x in st.get("nodes", []) if x["node_group_name"] == GROUP]:
        info = {"reachable": False}
        try:
            nc = node_conn(n)
            try:
                info.update(q(nc, """SELECT current_setting('server_version') AS pg_version,
                                            current_setting('server_version_num')::int AS pg_version_num,
                                            bdr.bdr_version() AS pgd_version,
                                            bdr.bdr_version_num() AS pgd_version_num,
                                            EXTRACT(EPOCH FROM pg_postmaster_start_time())::float8 AS started""")[0])
                r = q(nc, "SELECT status, message FROM bdr.monitor_local_replslots()")[0]
                h["checks"].append({"check": "replslots", "node": n, **r})
                info["slots"] = q(nc, """SELECT target_name, active, COALESCE(state, '') AS state, replay_lag_bytes,
                                                EXTRACT(EPOCH FROM replay_lag)::float8 AS replay_lag_seconds
                                         FROM bdr.node_slots WHERE target_name IS NOT NULL""")
                # Every replication slot on the node, not just the ones PGD maps to a peer: a slot
                # for a node that no longer exists keeps all WAL from its restart_lsn and fills the disk.
                info["all_slots"] = q(nc, """SELECT s.slot_name, s.active, COALESCE(s.wal_status, '') AS wal_status,
                                                    COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(), s.restart_lsn), 0)::float8
                                                        AS retained_bytes,
                                                    n.target_name,
                                                    CASE WHEN n.target_name IS NOT NULL THEN 'peer'
                                                         WHEN s.slot_name LIKE 'bdr\\_group\\_%' THEN 'group'
                                                         WHEN s.slot_name LIKE 'bdr\\_%' THEN 'orphan'
                                                         ELSE 'other' END AS kind
                                             FROM pg_replication_slots s
                                             LEFT JOIN bdr.node_slots n USING (slot_name)""")
                info["subs"] = q(nc, """SELECT origin_name, subscription_status, sub_enabled
                                        FROM bdr.subscription_summary WHERE origin_name IS NOT NULL""")
                info["reachable"] = True
            finally:
                nc.close()
        except Exception as e:
            info["error"] = str(e).splitlines()[0]
            h["errors"].append(f"{n}: {info['error']}")
        h["nodes"][n] = info

    try:
        h["operator"] = operator_status()
    except Exception:
        pass  # optional: not running under the PGD operator, or no RBAC

    # One overall verdict plus the issues behind it (severity 1 WARNING, 2 CRITICAL).
    issues = []
    for c in h["checks"]:
        sev = _health(c.get("status"))
        if sev:
            issues.append((min(sev, 2) if sev != 3 else 1, f"{c['check']} ({c['node']}): {c.get('message') or c.get('status')}"))
    for n, i in h["nodes"].items():
        if not i["reachable"]:
            issues.append((2, f"{n}: unreachable ({i.get('error', '?')})"))
        for s in i.get("slots", []):
            if not s["active"]:
                issues.append((1, f"slot {n} -> {s['target_name']} inactive"))
        for s in i.get("all_slots", []):
            gb = s["retained_bytes"] / 2**30
            if s["kind"] == "orphan":
                issues.append((2, f"orphaned slot {s['slot_name']} on {n} (no PGD node) is holding {gb:.1f} GiB of WAL"))
            elif not s["active"] and gb >= SLOT_WARN_GIB:
                issues.append((1, f"inactive slot {s['slot_name']} on {n} is holding {gb:.1f} GiB of WAL"))
        for s in i.get("subs", []):
            if not s["sub_enabled"]:
                issues.append((1, f"subscription {s['origin_name']} -> {n} disabled"))
            elif s["subscription_status"] != "replicating":
                issues.append((2, f"subscription {s['origin_name']} -> {n} {s['subscription_status']}"))
    if h["operator"] and not h["operator"]["ready"]:
        issues.append((1, f"operator: {h['operator']['phase']} - {h['operator']['message']}"))
    h["issues"] = issues
    h["overall"] = max([sev for sev, _ in issues], default=0)
    return h


def _int(v):
    try:
        return int(v)
    except Exception:
        return None


def safety_check(target, st=None):
    """Return a verdict on moving the write leader to `target`."""
    st = st or cluster_state()
    checks = []

    def add(cid, name, ok, detail, severity="block"):
        checks.append({"id": cid, "check": name, "ok": ok, "detail": detail, "severity": severity})

    leader = st.get("leader")
    add("1_different_node", "Target is a different data node", target in st.get("data_nodes", []) and target != leader,
        f"leader={leader}, target={target}")
    raft = st.get("raft", [{}])
    raft_ok = bool(raft) and str(raft[0].get("status", "")).upper() == "OK"
    add("2_raft", "Raft consensus healthy (majority available)", raft_ok, str(raft[0] if raft else "no data"))
    node = next((n for n in st.get("nodes", []) if n["node_name"] == target), None)
    add("3_target_active", "Target node ACTIVE", bool(node) and node["peer_state_name"] == "ACTIVE",
        node["peer_state_name"] if node else "unknown")

    lag = next((l for l in st.get("lag", []) if l["target_name"] == target), None)
    lag_bytes = _int(lag["replay_lag_bytes"]) if lag else None
    add("4_lag_drained", "Target has replayed everything the leader committed (replay_lag_bytes = 0)",
        lag_bytes == 0,
        f"replay_lag_bytes={lag_bytes}, replay_lag={lag['replay_lag'] if lag else '?'} "
        "(non-zero: a FAST switch would let the app re-insert rows the target hasn't seen yet; "
        "a STRICT switch waits for this to drain)", severity="warn")

    seqs = {s["seq"]: s["seqkind"] for s in st.get("sequences", [])}
    pn = st.get("per_node", {}).get(target, {})
    for table, (seq, _, _) in TABLES.items():
        kind = seqs.get(seq)
        row = pn.get(table, {})
        last = _int(row.get("seq_last_value"))
        mx = _int(row.get("table_max_id"))
        if kind == "local":
            nxt = (last or 0) + 1
            taken = _int(row.get("taken_next_1000")) or 0
            ok = taken == 0
            add(f"5_seq_{table}", f"{table}: LOCAL sequence on {target} won't re-issue existing ids", ok,
                f"next value on {target} = {nxt}; ids already used in {nxt}..{nxt + 999}: {taken}; "
                f"max(id) = {mx}. "
                + (f"{target} would hit DUPLICATE KEY on {taken} of its next 1000 inserts. "
                   "Fix: 'repair' (setval past max on every node) or 'convert' to a global sequence."
                   if not ok else
                   ("Safe for now, but the leader keeps writing past this node's counter; "
                    "a local sequence only stays safe if you convert it." if mx and nxt <= mx else "")))
        elif kind == "galloc":
            add(f"5_seq_{table}", f"{table}: galloc (unique by Raft-allocated chunks)", True,
                f"{target} spends its own chunk; expect ids to jump (last on target={last}, max={mx})",
                severity="info")
        elif kind:
            add(f"5_seq_{table}", f"{table}: {kind} (globally unique)", True,
                "ids embed node id + timestamp; may be numerically lower if clocks skew", severity="info")
    blocking = [c for c in checks if not c["ok"] and c["severity"] == "block"]
    warns = [c for c in checks if not c["ok"] and c["severity"] == "warn"]
    verdict = "UNSAFE" if blocking else ("WAIT (use strict)" if warns else "SAFE")
    return {"target": target, "leader": leader, "verdict": verdict, "checks": checks}


# --------------------------------------------------------------------------- Raft leader
RAFT_SCOPES = ("data", "parent")


def raft_group_for(scope, st):
    """'data' = the PGD data group (PGD_GROUP); 'parent' = the other Raft group (top-level group)."""
    if scope == "data":
        return GROUP
    others = sorted({r["node_group_name"] for r in st.get("raft_details", [])} - {GROUP})
    return others[0] if others else None


def raft_check(target, scope="data", st=None, reachable=None):
    """Return a verdict on moving the Raft leadership of a group to `target`."""
    st = st or cluster_state()
    checks = []

    def add(cid, name, ok, detail, severity="block"):
        checks.append({"id": cid, "check": name, "ok": ok, "detail": detail, "severity": severity})

    rgroup = raft_group_for(scope, st)
    leader = st.get("raft_leaders", {}).get(rgroup)
    members = {r["node_name"]: r for r in st.get("raft_details", []) if r["node_group_name"] == rgroup}
    add("1_group", f"Raft group found ({scope} group)", bool(rgroup), f"raft group = {rgroup}")
    add("2_different", "Target is not already the Raft leader", target != leader,
        f"raft leader = {leader}, target = {target}")
    m = members.get(target)
    add("3_member", "Target is a Raft member of the group", bool(m),
        f"state = {m['state']}" if m else f"{target} is not in {rgroup}'s Raft group")
    node = next((n for n in st.get("nodes", []) if n["node_name"] == target), None)
    add("4_active", "Target node ACTIVE", bool(node) and node["peer_state_name"] == "ACTIVE",
        node["peer_state_name"] if node else "unknown node")
    try:
        c = router()
        try:
            r = q(c, "SELECT status, message FROM bdr.monitor_group_raft(%s)", (rgroup,))[0]
        finally:
            c.close()
        add("5_consensus", "Raft consensus healthy (majority available)", str(r["status"]).upper() == "OK",
            r.get("message") or r["status"])
    except Exception as e:
        add("5_consensus", "Raft consensus healthy (majority available)", False, str(e).splitlines()[0])
    if reachable is None:
        try:
            node_conn(target).close()
            ok, detail = True, f"connected to {NODE_HOST_FMT.format(node=target)}"
        except Exception as e:
            ok, detail = False, str(e).splitlines()[0]
    else:
        ok, detail = bool(reachable.get(target)), "seen by the health collector"
    add("6_reachable", "Target reachable", ok, detail)
    add("7_write_leader", "Write leader is not moved", True,
        f"Raft leadership is the consensus role only; the write leader stays on {st.get('leader')}. "
        "Writes keep flowing; Raft-driven work (write-leader elections, galloc chunks, global DDL locks) "
        "is briefly paused while the new leader takes over.", "info")
    blocking = [c for c in checks if not c["ok"] and c["severity"] == "block"]
    return {"kind": "raft", "scope": scope, "raft_group": rgroup, "target": target, "leader": leader,
            "verdict": "UNSAFE" if blocking else "SAFE", "checks": checks}


# --------------------------------------------------------------------------- routes
def _str_ints(o):
    if isinstance(o, dict):
        return {k: _str_ints(v) for k, v in o.items()}
    if isinstance(o, list):
        return [_str_ints(v) for v in o]
    if isinstance(o, int) and not isinstance(o, bool) and abs(o) > 2**53:
        return str(o)
    return o


@app.get("/api/state")
def api_state():
    st = cluster_state()
    with lock:
        st["writer"] = {**writer_state, "stats": stats, "events": list(events)[:60],
                        "leader_changes": list(leader_changes)}
    st["tables"] = {t: v[2] for t, v in TABLES.items()}
    return jsonify(_str_ints(st))


@app.get("/api/raft_check/<scope>/<target>")
def api_raft_check(scope, target):
    if scope not in RAFT_SCOPES:
        return jsonify({"error": f"scope must be one of {RAFT_SCOPES}"}), 400
    return jsonify(raft_check(target, scope))


@app.post("/api/raft_switch")
def api_raft_switch():
    """Move the Raft leadership of the data or parent group to target, after the Raft safety check."""
    target = request.json["target"]
    scope = request.json.get("scope", "data")
    force = bool(request.json.get("force", False))
    if scope not in RAFT_SCOPES:
        return jsonify({"ok": False, "error": f"scope must be one of {RAFT_SCOPES}"}), 400
    chk = raft_check(target, scope)
    rgroup, leader = chk["raft_group"], chk["leader"]
    log("action", f"{who()}: Raft leader transfer requested ({rgroup}) {leader} -> {target}"
                  f"{' FORCED' if force else ''}")
    if chk["verdict"] != "SAFE" and not force:
        failed = [c["check"] for c in chk["checks"] if not c["ok"] and c["severity"] == "block"]
        log("action", f"Raft leader transfer -> {target} REFUSED: {'; '.join(failed)}")
        return jsonify({"ok": False, "refused": "Raft safety check says UNSAFE", "verdict": chk["verdict"],
                        "failed_checks": failed, "check": chk}), 409
    # Run it on the current Raft leader; fall back to the router if that fails.
    errors, result = [], None
    for host in ([leader] if leader else []) + [None]:
        try:
            c = node_conn(host) if host else router()
            try:
                q(c, "SET statement_timeout = '30s'")
                result = q(c, "SELECT bdr.raft_leadership_transfer(%s, true, %s) AS r", (target, rgroup))[0]["r"]
            finally:
                c.close()
            break
        except Exception as e:
            errors.append(f"{host or 'router'}: {str(e).splitlines()[0]}")
    if result is None:
        log("error", f"Raft leader transfer -> {target} failed: {' | '.join(errors)}")
        return jsonify({"ok": False, "error": errors}), 400
    now_leader = None
    for _ in range(10):
        time.sleep(1)
        now_leader = cluster_state().get("raft_leaders", {}).get(rgroup)
        if now_leader == target:
            break
    ok = now_leader == target
    log("action", f"Raft leader transfer ({rgroup}) result={result}; Raft leader is now {now_leader}")
    return jsonify({"ok": ok, "result": result, "raft_group": rgroup, "raft_leader_now": now_leader}), (200 if ok else 409)


@app.get("/api/check/<target>")
def api_check(target):
    return jsonify(safety_check(target))


@app.post("/api/switch")
def api_switch():
    target = request.json["target"]
    method = request.json.get("method", "strict")
    force = bool(request.json.get("force", False))
    log("action", f"{who()}: switchover requested -> {target} ({method}{', FORCED' if force else ''})")

    # Safety check first: refuse UNSAFE moves, and only allow STRICT while lag is outstanding.
    # 'force' skips this on purpose (the lab demonstrates what an unsafe move does).
    check = safety_check(target)
    if not force:
        refused = None
        if check["verdict"] == "UNSAFE":
            refused = "safety check says UNSAFE"
        elif check["verdict"].startswith("WAIT") and method != "strict":
            refused = "target still has replication lag: only a STRICT switchover is allowed"
        if refused:
            failed = [c["check"] for c in check["checks"] if not c["ok"] and c["severity"] in ("block", "warn")]
            log("action", f"switchover -> {target} ({method}) REFUSED: {refused}: {'; '.join(failed)}")
            return jsonify({"ok": False, "refused": refused, "verdict": check["verdict"],
                            "failed_checks": failed, "check": check}), 409
    c = router()
    try:
        r = q(c, "SELECT bdr.routing_leadership_transfer(%s, %s, %s, '10s') AS r",
              (GROUP, target, method))
        log("action", f"switchover result: {r}")
        return jsonify({"ok": True, "result": str(r)})
    except (psycopg2.OperationalError, psycopg2.InterfaceError) as e:
        # Connection Manager closes sessions on the old leader as leadership moves,
        # including the one that asked for the switch. Check where the leader is now.
        time.sleep(3)
        try:
            v = router()
            lead = q(v, "SELECT write_lead FROM bdr.node_group_routing_summary WHERE node_group_name = %s", (GROUP,))
            v.close()
            now_leader = lead[0]["write_lead"] if lead else None
        except Exception:
            now_leader = None
        ok = now_leader == target
        log("action", f"router closed the session during switchover (expected); write leader is now {now_leader}")
        return jsonify({"ok": ok, "write_leader_now": now_leader,
                        "note": "session closed by Connection Manager as leadership moved"}), (200 if ok else 409)
    except Exception as e:
        log("error", f"switchover failed: {str(e).splitlines()[0]}")
        return jsonify({"ok": False, "error": str(e)}), 400
    finally:
        try:
            c.close()
        except Exception:
            pass


@app.post("/api/repair")
def api_repair():
    """Fix a LOCAL sequence on every data node: move it past max(id).
    setval() on a local sequence only changes that node, so it is run per node."""
    table = request.json.get("table", "demo_local")
    seq = TABLES[table][0]
    margin = int(request.json.get("margin", 1000))
    st = cluster_state()
    out = {}
    for n in st["data_nodes"]:
        nc = node_conn(n)
        mx = q(nc, f"SELECT COALESCE(max(id),0) AS m FROM {table}")[0]["m"]
        q(nc, "SELECT setval(%s::regclass, %s)", (seq, mx + margin))
        out[n] = mx + margin
        nc.close()
    log("action", f"repaired {seq}: setval per node -> {out}")
    return jsonify({"ok": True, "setval": out})


@app.post("/api/convert")
def api_convert():
    """Permanent fix: convert the sequence to a PGD global sequence, starting above
    the highest id used on ANY node (plus margin, because sequences can't be locked)."""
    table = request.json.get("table", "demo_local")
    kind = request.json.get("kind", "galloc")
    seq = TABLES[table][0]
    st = cluster_state()
    mx = 0
    for n in st["data_nodes"]:
        nc = node_conn(n)
        mx = max(mx, q(nc, f"SELECT COALESCE(max(id),0) AS m FROM {table}")[0]["m"])
        nc.close()
    start = mx + 100000
    c = router()
    try:
        if kind == "galloc":
            q(c, "SELECT bdr.alter_sequence_set_kind(%s::regclass, 'galloc', %s)", (seq, start))
        else:
            q(c, "SELECT bdr.alter_sequence_set_kind(%s::regclass, %s)", (seq, kind))
    finally:
        c.close()
    log("action", f"converted {seq} to {kind} (start {start if kind=='galloc' else 'n/a'}, max seen {mx})")
    return jsonify({"ok": True, "start": start, "max_seen": mx})


@app.post("/api/reset_local")
def api_reset_local():
    """Put demo_local back to a LOCAL sequence so the duplicate-key demo can be re-run."""
    c = router()
    try:
        q(c, "SELECT bdr.alter_sequence_set_kind('demo_local_id_seq'::regclass, 'local')")
    finally:
        c.close()
    st = cluster_state()
    mx = 0
    for n in st["data_nodes"]:
        nc = node_conn(n)
        mx = max(mx, q(nc, "SELECT COALESCE(max(id),0) AS m FROM demo_local")[0]["m"])
        nc.close()
    for n in st["data_nodes"]:
        nc = node_conn(n)
        q(nc, "SELECT setval('demo_local_id_seq'::regclass, %s)", (mx + 1,))
        nc.close()
    log("action", f"demo_local_id_seq set back to LOCAL; every node's counter set to {mx + 1}. "
                  "Only the leader's counter will move from now on - the others fall behind.")
    return jsonify({"ok": True, "counters_set_to": mx + 1})


@app.post("/api/pause")
def api_pause():
    writer_state["paused"] = bool(request.json.get("paused", True))
    log("action", f"writer {'paused' if writer_state['paused'] else 'resumed'}")
    return jsonify({"ok": True, "paused": writer_state["paused"]})


# --------------------------------------------------------------------------- metrics
# Prometheus exposition of sections 2 (nodes/lag), 3 (sequences) and 4 (safety
# check for every possible target), for the Grafana dashboard. Computed on scrape.
VERDICT_CODE = {"SAFE": 0, "WAIT (use strict)": 1, "UNSAFE": 2}

def _num(v):
    try:
        return float(v)
    except Exception:
        return None

def _lbl(v):
    return str(v if v is not None else "").replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")

@app.get("/metrics")
def metrics():
    t0 = time.time()
    out = []

    def m(name, help_, samples):
        out.append(f"# HELP {name} {help_}")
        out.append(f"# TYPE {name} gauge")
        for labels, val in samples:
            val = _num(val)
            if val is None:
                continue
            labels = {"cluster": CLUSTER, "group": GROUP, **labels}
            ls = ",".join(f'{k}="{_lbl(v)}"' for k, v in labels.items())
            out.append(f"{name}{{{ls}}} {val!r}" if ls else f"{name} {val!r}")

    st = cluster_state()
    leader = st.get("leader")
    nodes = [n for n in st.get("nodes", []) if n["node_group_name"] == GROUP]
    raft = (st.get("raft") or [{}])[0]

    # --- section 2: nodes and replication lag from the write leader
    m("pgd_demo_state_errors", "Errors while collecting cluster state",
      [({}, len(st.get("errors", [])))])
    m("pgd_demo_info", "Demo app instance (always 1); labels carry PGD version and the app / pgAdmin URLs",
      [({"pgd_version": st.get("pgd_version", "unknown"), "app_url": APP_URL, "pgadmin_url": PGADMIN_URL}, 1)])
    m("pgd_demo_raft_ok", "1 if Raft consensus reports OK",
      [({}, 1 if str(raft.get("status", "")).upper() == "OK" else 0)])
    rd = st.get("raft_details", [])
    rleaders = st.get("raft_leaders", {})

    def scope(g):
        return "data group" if g == GROUP else "parent group"

    m("pgd_demo_raft_leader", "1 if this node is the Raft leader of raft_group (the data group or its parent)",
      [({"raft_group": r["node_group_name"], "scope": scope(r["node_group_name"]), "node": r["node_name"]},
        1 if rleaders.get(r["node_group_name"]) == r["node_name"] else 0) for r in rd])
    m("pgd_demo_raft_node_state", "Raft state of this node in raft_group (always 1); label carries the state",
      [({"raft_group": r["node_group_name"], "node": r["node_name"], "state": r["state"]}, 1) for r in rd])
    terms = {}
    for r in rd:
        terms[r["node_group_name"]] = max(terms.get(r["node_group_name"], 0), _num(r["current_term"]) or 0)
    m("pgd_demo_raft_term", "Current Raft term of raft_group (increments on every Raft election)",
      [({"raft_group": g, "scope": scope(g)}, t) for g, t in terms.items()])
    m("pgd_demo_node_info", "PGD node (always 1); labels carry kind and peer state",
      [({"node": n["node_name"], "kind": n["node_kind"] or "?", "state": n["peer_state_name"]}, 1) for n in nodes])
    m("pgd_demo_node_active", "1 if peer_state_name = ACTIVE",
      [({"node": n["node_name"]}, 1 if n["peer_state_name"] == "ACTIVE" else 0) for n in nodes])
    m("pgd_demo_write_leader", "1 if this node is the group's write leader",
      [({"node": n["node_name"]}, 1 if n["node_name"] == leader else 0) for n in nodes])
    lag = st.get("lag", [])
    m("pgd_demo_replay_lag_bytes", "bdr.node_slots.replay_lag_bytes from the write leader to this node",
      [({"node": l["target_name"]}, l["replay_lag_bytes"]) for l in lag])
    m("pgd_demo_replay_lag_seconds", "bdr.node_slots.replay_lag from the write leader to this node",
      [({"node": l["target_name"]}, l.get("replay_lag_seconds") if l.get("replay_lag_seconds") is not None else 0) for l in lag])
    m("pgd_demo_slot_info", "Replication slot from the write leader (always 1); label carries slot state",
      [({"node": l["target_name"], "slot_state": l["state"]}, 1) for l in lag])

    # --- section 3: sequences
    kinds = {s["seq"]: s["seqkind"] for s in st.get("sequences", [])}
    m("pgd_demo_sequence_kind", "Sequence kind from bdr.sequences (always 1)",
      [({"table": t, "sequence": seq, "kind": kinds.get(seq, "?")}, 1) for t, (seq, _, _) in TABLES.items()])
    per = st.get("per_node", {})
    m("pgd_demo_node_query_ok", "1 if the per-node sequence queries succeeded",
      [({"node": n}, 0 if "error" in info else 1) for n, info in per.items()])
    rows = [(n, t, kinds.get(TABLES[t][0], "?"), r) for n, info in per.items() if "error" not in info
            for t, r in info.items()]
    m("pgd_demo_sequence_last_value", "pg_sequences.last_value read on this node",
      [({"node": n, "table": t, "kind": k}, r.get("seq_last_value")) for n, t, k, r in rows])
    m("pgd_demo_table_max_id", "max(id) of the table read on this node",
      [({"node": n, "table": t, "kind": k}, r.get("table_max_id")) for n, t, k, r in rows])
    m("pgd_demo_table_rows", "count(*) of the table read on this node",
      [({"node": n, "table": t, "kind": k}, r.get("rows")) for n, t, k, r in rows])
    m("pgd_demo_sequence_dup_risk", "LOCAL sequences only: ids already used among this node's next 1000 values "
                                    "(duplicate keys if this node leads); 0 for global kinds",
      [({"node": n, "table": t, "kind": k}, (r.get("taken_next_1000") or 0) if k == "local" else 0)
       for n, t, k, r in rows])
    chunks = [(n, t, i, c) for n, t, k, r in rows for i, c in enumerate(r.get("chunks") or []) if "error" not in c]
    m("pgd_demo_galloc_chunk_start", "Start of a galloc chunk held by this node",
      [({"node": n, "table": t, "chunk": i}, c.get("chunk_start")) for n, t, i, c in chunks])
    m("pgd_demo_galloc_chunk_end", "End of a galloc chunk held by this node",
      [({"node": n, "table": t, "chunk": i}, c.get("chunk_end")) for n, t, i, c in chunks])

    # --- section 4: is it safe to move the write leader to each node?
    verdicts, statuses = [], []
    for target in st.get("data_nodes", []):
        if target == leader:
            verdicts.append(({"target": target}, -1))
            continue
        res = safety_check(target, st)
        verdicts.append(({"target": target}, VERDICT_CODE.get(res["verdict"], 2)))
        for c in res["checks"]:
            status = 0 if c["ok"] else (1 if c["severity"] == "warn" else 2 if c["severity"] == "block" else 0)
            statuses.append(({"target": target, "check_id": c["id"], "check": c["check"],
                              "severity": c["severity"]}, status))
    m("pgd_demo_switch_verdict", "Safety of moving the write leader to target: "
                                 "-1 current leader, 0 SAFE, 1 WAIT (use strict), 2 UNSAFE", verdicts)
    m("pgd_demo_switch_check_status", "Individual safety check: 0 PASS, 1 WAIT, 2 FAIL", statuses)

    # --- health, versions and the replication mesh
    h = health_state(st)
    m("pgd_demo_overall_health", "Overall PGD health: 0 HEALTHY, 1 WARNING, 2 CRITICAL (see pgd_demo_health_issue)",
      [({}, h["overall"])])
    m("pgd_demo_health_issue", "One current health problem; value is its severity (1 WARNING, 2 CRITICAL)",
      [({"issue": msg[:200]}, sev) for sev, msg in h["issues"]])
    m("pgd_demo_health_check", "PGD monitoring function status: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN; "
                               "node='group' for group-wide checks",
      [({"check": c["check"], "node": c["node"], "message": str(c.get("message") or "")[:200]},
        _health(c.get("status"))) for c in h["checks"]])
    if h["operator"]:
        op = h["operator"]
        m("pgd_demo_operator_ready", "1 if the EDB PGD operator reports the PGDGroup Ready; labels carry its phase",
          [({"phase": op["phase"], "message": op["message"][:200]}, 1 if op["ready"] else 0)])
    nodes_h = h["nodes"].items()
    m("pgd_demo_node_reachable", "1 if the app could connect to this node directly",
      [({"node": n}, 1 if i["reachable"] else 0) for n, i in nodes_h])
    up = [(n, i) for n, i in nodes_h if i["reachable"]]
    m("pgd_demo_node_version_info", "Postgres and PGD version running on this node (always 1)",
      [({"node": n, "pg_version": i["pg_version"], "pgd_version": i["pgd_version"]}, 1) for n, i in up])
    m("pgd_demo_node_pg_version_num", "server_version_num on this node", [({"node": n}, i["pg_version_num"]) for n, i in up])
    m("pgd_demo_node_pgd_version_num", "bdr.bdr_version_num() on this node", [({"node": n}, i["pgd_version_num"]) for n, i in up])
    m("pgd_demo_node_start_time_seconds", "Postgres postmaster start time (unix seconds) on this node",
      [({"node": n}, i["started"]) for n, i in up])
    slots = [(n, s) for n, i in up for s in i.get("slots", [])]
    m("pgd_demo_mesh_slot_active", "1 if the replication slot on source for target is active",
      [({"source": n, "target": s["target_name"]}, 1 if s["active"] else 0) for n, s in slots])
    m("pgd_demo_mesh_slot_info", "Replication slot on source for target (always 1); label carries its state",
      [({"source": n, "target": s["target_name"], "slot_state": s["state"] or "-"}, 1) for n, s in slots])
    m("pgd_demo_mesh_lag_bytes", "bdr.node_slots.replay_lag_bytes from source to target",
      [({"source": n, "target": s["target_name"]}, s["replay_lag_bytes"]) for n, s in slots])
    m("pgd_demo_mesh_lag_seconds", "bdr.node_slots.replay_lag from source to target",
      [({"source": n, "target": s["target_name"]}, s["replay_lag_seconds"] or 0) for n, s in slots])
    allslots = [(n, s) for n, i in up for s in i.get("all_slots", [])]
    m("pgd_demo_node_slot_retained_bytes", "WAL this node keeps for each replication slot "
                                           "(pg_current_wal_lsn - restart_lsn). kind: peer (slot for a PGD node), "
                                           "group, orphan (bdr slot with no PGD node: fills the disk), other",
      [({"node": n, "slot": s["slot_name"], "kind": s["kind"], "target": s["target_name"] or "-",
         "active": str(bool(s["active"])).lower(), "wal_status": s["wal_status"] or "-"}, s["retained_bytes"])
       for n, s in allslots])
    m("pgd_demo_node_orphan_slots", "Replication slots on this node that belong to no PGD node",
      [({"node": n}, sum(1 for s in i.get("all_slots", []) if s["kind"] == "orphan")) for n, i in up])
    subs = [(n, s) for n, i in up for s in i.get("subs", [])]
    m("pgd_demo_subscription_replicating", "1 if target's subscription to source is enabled and replicating; "
                                           "label carries subscription_status",
      [({"source": s["origin_name"], "target": n, "status": s["subscription_status"]},
        1 if s["sub_enabled"] and s["subscription_status"] == "replicating" else 0) for n, s in subs])
    m("pgd_demo_health_collect_errors", "Errors while collecting health data", [({}, len(h["errors"]))])

    # --- Raft leader move verdicts (for every Raft member, data and parent group)
    reach = {n: i["reachable"] for n, i in h["nodes"].items()}
    rv = []
    for scope in RAFT_SCOPES:
        rgroup = raft_group_for(scope, st)
        members = sorted({r["node_name"] for r in st.get("raft_details", []) if r["node_group_name"] == rgroup})
        for t in members:
            if t == st.get("raft_leaders", {}).get(rgroup):
                rv.append(({"scope": f"{scope} group", "kind": f"raft-{scope}", "raft_group": rgroup, "target": t}, -1))
            else:
                v = raft_check(t, scope, st, reach)["verdict"]
                rv.append(({"scope": f"{scope} group", "kind": f"raft-{scope}", "raft_group": rgroup, "target": t},
                           0 if v == "SAFE" else 2))
    m("pgd_demo_raft_switch_verdict", "Safety of moving the Raft leadership of raft_group to target: "
                                      "-1 current Raft leader, 0 SAFE, 2 UNSAFE", rv)

    m("pgd_demo_metrics_duration_seconds", "Time taken to build this metrics page",
      [({}, time.time() - t0)])
    return Response("\n".join(out) + "\n", mimetype="text/plain; version=0.0.4")


@app.get("/healthz")
def healthz():
    return "ok"


@app.get("/switch")
def switch_page():
    """Safety-checked switchover page (linked from the Grafana dashboard: /switch?target=<node>)."""
    return Response(open(os.path.join(os.path.dirname(__file__), "switch.html")).read(),
                    mimetype="text/html")


@app.get("/")
def index():
    return Response(open(os.path.join(os.path.dirname(__file__), "index.html")).read(),
                    mimetype="text/html")


def start():
    for i in range(60):
        try:
            setup_schema()
            break
        except Exception as e:
            print("setup retry", e, flush=True)
            time.sleep(5)
    threading.Thread(target=writer_loop, daemon=True).start()


start()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, threaded=True)
