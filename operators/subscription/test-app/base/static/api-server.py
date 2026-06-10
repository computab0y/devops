#!/usr/bin/env python3
"""
Stateful mock API server for the Units Management API.
Uses Python stdlib only — no external dependencies required.
Data is loaded from JSON files at startup and held in memory.
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
import json, re, os, copy

DATA_DIR = os.environ.get("DATA_DIR", "/data")

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        print(f"WARN: could not load {path}: {e}")
        return []

# ----- In-memory state (loaded at startup) -----
agents       = load_json(f"{DATA_DIR}/endpoints.json")       # trading agents + nested unitEndpoints
unit_eps     = load_json(f"{DATA_DIR}/unit-endpoints.json")  # flat unit endpoints list
print(f"Loaded {len(agents)} trading agents, {len(unit_eps)} unit endpoints")

# ----- Helper -----
def agent_for(endpoint_id):
    return next((a for a in agents if a["tradingAgentId"] == endpoint_id), None)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"{self.command} {self.path} -> {args[0] if args else ''}")

    # ---------- read body ----------
    def body(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length)) if length else {}

    # ---------- send response ----------
    def respond(self, status, data):
        payload = json.dumps(data, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Accept, Authorization")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
        self.send_header("Content-Length", len(payload))
        self.end_headers()
        self.wfile.write(payload)

    def respond_empty(self, status):
        self.send_response(status)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", "0")
        self.end_headers()

    # ---------- OPTIONS preflight ----------
    def do_OPTIONS(self):
        self.respond_empty(204)

    # ============================= GET =============================
    def do_GET(self):
        p = self.path.split("?")[0]

        if p == "/endpoints":
            self.respond(200, agents)

        elif p == "/unitEndpoints":
            self.respond(200, unit_eps)

        elif m := re.fullmatch(r"/unitEndpoints/(.+)", p):
            uid = m.group(1)
            result = [u for u in unit_eps if u.get("unitRegId") == uid]
            self.respond(200 if result else 404, result or {"error": "not found"})

        elif p == "/units":
            units = list({u["unitRegId"] for u in unit_eps})
            self.respond(200, [{"unitRegId": u} for u in sorted(units)])

        elif p == "/unitGroups":
            self.respond(200, [])

        elif p == "/unitGroupMembers":
            self.respond(200, [])

        elif p == "/zones":
            self.respond(200, [])

        elif p == "/contracts":
            self.respond(200, [])

        elif p == "/unitState":
            self.respond(200, [])

        else:
            self.respond(404, {"error": "not found"})

    # ============================= POST ============================
    def do_POST(self):
        p = self.path.split("?")[0]

        if p == "/unitEndpoints":
            data = self.body()
            required = ["unitRegId", "endpointId"]
            missing = [k for k in required if not data.get(k)]
            if missing:
                self.respond(400, {"error": f"missing fields: {missing}"})
                return

            entry = {
                "unitRegId":          data["unitRegId"],
                "endpointId":         data["endpointId"],
                "unitEndpointStatus": data.get("unitEndpointStatus", "UP"),
                "effectiveStartDate": data.get("effectiveStartDate", ""),
            }

            # Add to flat list
            unit_eps.append(entry)

            # Link into nested agents list
            agent = agent_for(data["endpointId"])
            if agent:
                agent.setdefault("unitEndpoints", []).append({
                    "unitRegId":          entry["unitRegId"],
                    "unitEndpointStatus": entry["unitEndpointStatus"],
                    "effectiveStartDate": entry["effectiveStartDate"],
                })

            self.respond(201, {"status": "created", "data": entry})

        elif p == "/scheduledTask":
            self.respond(200, {"status": "task triggered"})

        elif p in ("/units", "/zones", "/endpoints"):
            data = self.body()
            self.respond(201, {"status": "created", "data": data})

        else:
            self.respond(405, {"error": "method not allowed"})

    # ============================= PATCH ===========================
    def do_PATCH(self):
        p = self.path.split("?")[0]

        if m := re.fullmatch(r"/unitEndpoints/(.+)", p):
            uid = m.group(1)
            updates = self.body()
            updated = False

            for u in unit_eps:
                if u.get("unitRegId") == uid:
                    u.update({k: v for k, v in updates.items() if k != "unitRegId"})
                    updated = True

            # Sync into agents
            for agent in agents:
                for ue in agent.get("unitEndpoints", []):
                    if ue.get("unitRegId") == uid:
                        ue.update({k: v for k, v in updates.items()
                                   if k not in ("unitRegId", "endpointId")})

            self.respond(200 if updated else 404,
                         {"status": "updated"} if updated else {"error": "not found"})

        elif m := re.fullmatch(r"/unitState/(.+)", p):
            self.respond(200, {"status": "state updated"})

        else:
            self.respond(405, {"error": "method not allowed"})

    # ============================= DELETE ==========================
    def do_DELETE(self):
        p = self.path.split("?")[0]
        global unit_eps

        if m := re.fullmatch(r"/unitEndpoints/(.+)", p):
            uid = m.group(1)
            before = len(unit_eps)
            unit_eps = [u for u in unit_eps if u.get("unitRegId") != uid]

            # Remove from agents
            for agent in agents:
                agent["unitEndpoints"] = [
                    ue for ue in agent.get("unitEndpoints", [])
                    if ue.get("unitRegId") != uid
                ]

            if len(unit_eps) < before:
                self.respond_empty(204)
            else:
                self.respond(404, {"error": "not found"})

        elif p == "/unitState":
            self.respond_empty(204)

        elif m := re.fullmatch(r"/zones/(.+)", p):
            self.respond_empty(204)

        elif m := re.fullmatch(r"/endpoints/(.+)", p):
            self.respond_empty(204)

        else:
            self.respond(405, {"error": "method not allowed"})

    # ============================= PUT =============================
    def do_PUT(self):
        p = self.path.split("?")[0]
        data = self.body()
        self.respond(200, {"status": "updated", "data": data})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 8080))
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"API server listening on port {port}")
    server.serve_forever()
