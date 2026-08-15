#!/usr/bin/env python3
"""
sample-app: a minimal status service demonstrating the full
GitHub -> Tekton -> ArgoCD -> Vault -> Grafana pipeline.
Stdlib only — no external dependencies required.
"""
from http.server import HTTPServer, BaseHTTPRequestHandler
from datetime import datetime, timezone
import json, os

PORT = int(os.environ.get("PORT", 8080))
BUILD_VERSION = os.environ.get("BUILD_VERSION", "dev")
GREETING = os.environ.get("GREETING")  # populated from Vault via External Secrets


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"{self.command} {self.path} -> {args[0] if args else ''}")

    def respond_json(self, status, data):
        payload = json.dumps(data, indent=2).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", len(payload))
        self.end_headers()
        self.wfile.write(payload)

    def respond_html(self, status, html):
        payload = html.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", len(payload))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        path = self.path.split("?")[0]

        if path == "/healthz":
            self.respond_json(200, {"status": "ok"})
            return

        if path == "/api/status":
            self.respond_json(200, {
                "app": "sample-app",
                "version": BUILD_VERSION,
                "vault_secret_loaded": bool(GREETING),
                "time": datetime.now(timezone.utc).isoformat(),
            })
            return

        if path == "/":
            vault_line = (
                "Vault credential loaded ✔"
                if GREETING else
                "Vault credential NOT loaded ✘"
            )
            self.respond_html(200, f"""<!doctype html>
<html>
<head><title>sample-app</title></head>
<body style="font-family: sans-serif; margin: 3rem;">
  <h1>sample-app</h1>
  <p>Version: <b>{BUILD_VERSION}</b></p>
  <p>{vault_line}</p>
  <p><a href="/api/status">/api/status</a></p>
</body>
</html>""")
            return

        self.respond_json(404, {"error": "not found"})


if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    print(f"sample-app listening on port {PORT} (version={BUILD_VERSION})")
    server.serve_forever()
