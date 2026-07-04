# How to Build a Keycloak → Vault Sync Pipeline in Tekton

This guide walks you through building a Tekton pipeline that reads user credentials from
Keycloak and stores them in HashiCorp Vault. Every step builds on the last — by the end
you will have a working pipeline you can run from the OpenShift console or CLI.

---

## What You Are Building

```
OCP Console / tkn CLI
        │
        ▼
  Tekton Pipeline  ──► Task (python:3.11-slim container)
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
                Keycloak           HashiCorp Vault
          (read users + attrs)   (write credentials)
```

The pipeline:
1. Authenticates to Keycloak as admin
2. Fetches all users in a given realm that have a specific OU attribute
3. Writes their usernames and passwords to Vault KV v2

---

## Prerequisites

| Requirement | Notes |
|---|---|
| OpenShift / OKD cluster | 4.12 or later |
| OpenShift Pipelines operator | Install from OperatorHub |
| Keycloak | RHBK or upstream Keycloak, reachable from cluster pods |
| HashiCorp Vault | KV v2 enabled (see Step 2) |
| `oc` CLI | Logged in with cluster-admin or pipelines namespace admin |
| `tkn` CLI | v0.40+ |
| Container image | `python:3.11-slim` — mirror to internal registry if disconnected |

---

## Step 1 — Prepare Keycloak

The pipeline reads two custom attributes from each user: `OU` (to filter which users to sync)
and `password` (the credential to store in Vault). You need to set these on your users before
the pipeline will pick them up.

### 1a. Create a realm (skip if you have one)

In the Keycloak admin console:
- Top-left dropdown → **Create realm**
- Name it (e.g. `my-realm`) → **Create**

### 1b. Add users with the required attributes

For each user you want synced:

1. **Users** → **Add user** → set username → **Create**
2. **Credentials** tab → set a password (this is the Keycloak login password, separate from the synced credential)
3. **Attributes** tab → add two attributes:

| Key | Value | Notes |
|---|---|---|
| `OU` | `my-group` | The value your pipeline will filter on — change to match your group name |
| `password` | `their-synced-password` | The credential that will be written to Vault |

> **Why a custom `password` attribute?** Keycloak does not expose hashed passwords via
> its API. Storing the credential as a plain-text attribute is a deliberate design
> choice — it is separate from the Keycloak login password and is what gets synced to Vault.

### 1c. Get your Keycloak admin credentials and internal URL

You will need:
- Admin username and password (for the `master` realm admin)
- The **internal** Keycloak URL (pod-to-pod, not the external route)

Example internal URL: `http://keycloak-service.keycloak.svc:8080`

Find it by running:
```bash
oc get svc -n keycloak
```

---

## Step 2 — Prepare Vault

### 2a. Enable KV v2

If Vault is in dev mode this is already done. For a production Vault:

```bash
export VAULT_ADDR=http://vault.vault.svc:8200
export VAULT_TOKEN=<your-root-or-admin-token>

vault secrets enable -path=secret kv-v2
```

Verify:
```bash
vault secrets list
# secret/ should appear with type kv
```

### 2b. Create a scoped token for the pipeline

Do not use the root token in production. Create a policy that allows only what the pipeline needs:

```hcl
# pipeline-policy.hcl
path "secret/data/synced-users" {
  capabilities = ["create", "read", "update"]
}
```

```bash
vault policy write pipeline-policy pipeline-policy.hcl
vault token create -policy=pipeline-policy -ttl=8760h
# Copy the token value — you will need it in Step 4
```

### 2c. Get your Vault internal URL

```bash
oc get svc -n vault
# e.g. http://vault.vault.svc:8200
```

---

## Step 3 — Create the ConfigMap

The ConfigMap holds all non-sensitive configuration. Create a file called `pipeline-config.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: pipeline-config
  namespace: openshift-pipelines-operator   # change if using a different namespace
data:
  keycloak-url: "http://keycloak-service.keycloak.svc:8080"  # internal Keycloak URL
  vault-address: "http://vault.vault.svc:8200"                # internal Vault URL
  vault-secret-users: "synced-users"                          # Vault KV path to write to
```

Apply it:
```bash
oc apply -f pipeline-config.yaml
```

---

## Step 4 — Create the Secrets

### Keycloak admin credentials

Create `pipeline-env-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: pipeline-env
  namespace: openshift-pipelines-operator
type: Opaque
stringData:
  keycloak-admin-username: "admin"           # your Keycloak master realm admin
  keycloak-admin-password: "your-password"   # admin password
```

### Vault token

Create `vault-token-secret.yaml`:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-token
  namespace: openshift-pipelines-operator
type: Opaque
stringData:
  token: "your-vault-token"   # the token created in Step 2b
```

Apply both:
```bash
oc apply -f pipeline-env-secret.yaml
oc apply -f vault-token-secret.yaml
```

> **Security note:** Do not commit these files to git with real values.
> Use `REPLACE_ME` placeholders in the committed versions and apply real values manually
> or via a secrets management tool.

---

## Step 5 — Write the Task

This is the heart of the pipeline. Create `keycloak-vault-sync-task.yaml`.

Work through it in sections:

### 5a. Task header and params

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: keycloak-vault-sync
  namespace: openshift-pipelines-operator
spec:
  params:
  - name: target-ou
    type: string
    description: "Keycloak OU attribute value to filter users by"
    default: "my-group"
  - name: keycloak-realm
    type: string
    description: "Keycloak realm to sync from"
    default: "my-realm"
  - name: vault-address
    type: string
    description: "Vault server address"
    default: "http://vault.vault.svc:8200"
```

Params are values the user supplies at run time. Tekton substitutes `$(params.name)` as a
simple string replacement before the container starts — it is not a runtime env var.

### 5b. Step definition — image and env vars

```yaml
  steps:
  - name: sync
    image: python:3.11-slim        # mirror this to your internal registry if disconnected
    securityContext:
      runAsUser: 0
    env:
    - name: VAULT_TOKEN
      valueFrom:
        secretKeyRef:
          name: vault-token
          key: token
    - name: KEYCLOAK_URL
      valueFrom:
        configMapKeyRef:
          name: pipeline-config
          key: keycloak-url
    - name: VAULT_SECRET_USERS
      valueFrom:
        configMapKeyRef:
          name: pipeline-config
          key: vault-secret-users
    - name: KEYCLOAK_ADMIN_USERNAME
      valueFrom:
        secretKeyRef:
          name: pipeline-env
          key: keycloak-admin-username
    - name: KEYCLOAK_ADMIN_PASSWORD
      valueFrom:
        secretKeyRef:
          name: pipeline-env
          key: keycloak-admin-password
```

### 5c. The script

```yaml
    script: |
      #!/usr/bin/env python3
      import os, sys, json, ssl, urllib.request

      # Values from params (Tekton substitutes these before the container starts)
      VAULT_ADDR         = "$(params.vault-address)"
      TARGET_OU          = "$(params.target-ou)"
      KEYCLOAK_REALM     = "$(params.keycloak-realm)"

      # Values from env vars (injected from ConfigMap / Secret)
      KEYCLOAK_URL       = os.environ.get("KEYCLOAK_URL")
      VAULT_SECRET_USERS = os.environ.get("VAULT_SECRET_USERS")
      VAULT_TOKEN        = os.environ.get("VAULT_TOKEN")

      # Disable SSL verification — safe for internal cluster traffic
      ctx = ssl.create_default_context()
      ctx.check_hostname = False
      ctx.verify_mode    = ssl.CERT_NONE

      # ── 1. Get Keycloak admin token ──────────────────────────────────────────
      def keycloak_admin_token():
          username = os.environ.get("KEYCLOAK_ADMIN_USERNAME")
          password = os.environ.get("KEYCLOAK_ADMIN_PASSWORD")
          url  = f"{KEYCLOAK_URL}/realms/master/protocol/openid-connect/token"
          data = f"client_id=admin-cli&username={username}&password={password}&grant_type=password".encode()
          try:
              with urllib.request.urlopen(
                  urllib.request.Request(url, data=data), context=ctx, timeout=10
              ) as r:
                  return json.loads(r.read().decode())["access_token"]
          except Exception as e:
              print(f"ERROR: Keycloak auth failed at {KEYCLOAK_URL}: {e}")
              sys.exit(1)

      # ── 2. Fetch users from Keycloak realm ───────────────────────────────────
      def get_users_in_ou(target_ou):
          token = keycloak_admin_token()
          # briefRepresentation=false returns attributes in one call — avoids N+1
          url = f"{KEYCLOAK_URL}/admin/realms/{KEYCLOAK_REALM}/users?briefRepresentation=false&max=1000"
          req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
          try:
              with urllib.request.urlopen(req, context=ctx) as r:
                  users = json.loads(r.read().decode())
              result = []
              for u in users:
                  attrs   = u.get("attributes", {})
                  pw_list = attrs.get("password", [])
                  if any(target_ou.lower() == ou.lower() for ou in attrs.get("OU", [])):
                      result.append({"username": u["username"], "password": pw_list[0] if pw_list else None})
              return result
          except Exception as e:
              print(f"ERROR: Failed to fetch users from Keycloak realm '{KEYCLOAK_REALM}': {e}")
              sys.exit(1)

      # ── 3. Read current Vault state ──────────────────────────────────────────
      def vault_read(path):
          req = urllib.request.Request(
              f"{VAULT_ADDR}/v1/secret/data/{path}",
              headers={"X-Vault-Token": VAULT_TOKEN}
          )
          try:
              with urllib.request.urlopen(req) as r:
                  return json.loads(r.read().decode()).get("data", {}).get("data", {})
          except Exception as e:
              print(f"ERROR: Vault read '{path}' failed: {e}")
              sys.exit(1)

      # ── 4. Write to Vault ────────────────────────────────────────────────────
      def vault_write(path, data):
          req = urllib.request.Request(
              f"{VAULT_ADDR}/v1/secret/data/{path}",
              data=json.dumps({"data": data}).encode(),
              headers={"X-Vault-Token": VAULT_TOKEN, "Content-Type": "application/json"},
              method="POST"
          )
          try:
              with urllib.request.urlopen(req):
                  print(f"Vault '{path}' updated.")
          except Exception as e:
              print(f"ERROR: Vault write '{path}' failed: {e}")
              sys.exit(1)

      # ── 5. Sync ──────────────────────────────────────────────────────────────
      def sync_to_vault(users):
          existing = vault_read(VAULT_SECRET_USERS)
          changed  = False
          for u in users:
              if u["password"] and existing.get(u["username"]) != u["password"]:
                  existing[u["username"]] = u["password"]
                  changed = True
          if changed:
              vault_write(VAULT_SECRET_USERS, existing)
          else:
              print("No changes — Vault is already up to date.")

      # ── Main ─────────────────────────────────────────────────────────────────
      print(f"Fetching users in OU '{TARGET_OU}' from realm '{KEYCLOAK_REALM}' at {KEYCLOAK_URL}...")
      users   = get_users_in_ou(TARGET_OU)
      synced  = [u["username"] for u in users if u["password"]]
      skipped = [u["username"] for u in users if not u["password"]]

      print(f"Found {len(users)} user(s) in OU '{TARGET_OU}': {[u['username'] for u in users]}")
      if skipped:
          print(f"Warning: {len(skipped)} user(s) skipped — no password attribute set: {skipped}")

      if not synced:
          print("No users to sync — exiting.")
          sys.exit(0)

      sync_to_vault(users)

      print(f"\n{'='*50}")
      print(f"  Sync complete: {len(synced)} user(s) written to Vault")
      print(f"{'='*50}")
      vault_users = vault_read(VAULT_SECRET_USERS)
      if vault_users:
          print(f"\nUsers now in Vault (secret/{VAULT_SECRET_USERS}):")
          for u in sorted(vault_users.keys()):
              print(f"  - {u}")
      print(f"{'='*50}\n")
```

Apply the task:
```bash
oc apply -f keycloak-vault-sync-task.yaml
```

Verify it was accepted:
```bash
oc get task keycloak-vault-sync -n openshift-pipelines-operator
```

---

## Step 6 — Write the Pipeline

The Pipeline wraps the Task and is what users interact with (via console or CLI).
Create `keycloak-vault-sync-pipeline.yaml`:

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: keycloak-vault-sync
  namespace: openshift-pipelines-operator
spec:
  params:
  - name: target-ou
    type: string
    description: "Keycloak OU attribute to filter users by"
    default: "my-group"
  - name: keycloak-realm
    type: string
    description: "Keycloak realm to sync from"
    default: "my-realm"
  - name: vault-address
    type: string
    description: "Vault server address"
    default: "http://vault.vault.svc:8200"
  tasks:
  - name: sync-users
    taskRef:
      name: keycloak-vault-sync
    params:
    - name: target-ou
      value: $(params.target-ou)
    - name: keycloak-realm
      value: $(params.keycloak-realm)
    - name: vault-address
      value: $(params.vault-address)
```

Apply it:
```bash
oc apply -f keycloak-vault-sync-pipeline.yaml
```

---

## Step 7 — Enable the Console Plugin (for param dropdowns)

Without this the OCP console Start screen will not show the parameter fields:

```bash
oc patch console.operator cluster --type=merge \
  -p '{"spec":{"plugins":["pipelines-console-plugin"]}}'
```

---

## Step 8 — Run and Verify

### Run via CLI

```bash
tkn pipeline start keycloak-vault-sync \
  -p target-ou=my-group \
  -p keycloak-realm=my-realm \
  -p vault-address=http://vault.vault.svc:8200 \
  -n openshift-pipelines-operator

# Watch the logs
tkn pipelinerun logs --last -f -n openshift-pipelines-operator
```

### Run via OCP console

Pipelines → `keycloak-vault-sync` → **Start** → fill in the three params → **Start**

### Verify users landed in Vault

```bash
# Port-forward to Vault
oc port-forward svc/vault 8200:8200 -n vault &

# Read the secret
curl -s -H "X-Vault-Token: your-token" \
  http://localhost:8200/v1/secret/data/synced-users | jq .data.data
```

Expected output:
```json
{
  "user1": "their-synced-password",
  "user2": "their-synced-password"
}
```

---

## Troubleshooting

### Pipeline run fails — check the logs first
```bash
tkn pipelinerun logs --last -f -n openshift-pipelines-operator
```

### Keycloak auth fails
- Confirm the pod can reach Keycloak: `oc exec -it <pod> -- curl http://keycloak-service.keycloak.svc:8080/realms/master`
- Confirm admin credentials in the Secret are correct
- The pipeline always authenticates to the **master** realm, even when syncing users from another realm

### No users returned
- Check the `OU` attribute is set exactly (case-insensitive match is applied)
- Check `briefRepresentation=false` is in the URL — without it attributes are not returned
- Confirm the realm name in the param matches the actual realm

### Vault write fails
- Confirm KV v2 is enabled: `vault secrets list` should show `secret/` with type `kv`
- Confirm the token has write access to `secret/data/synced-users`
- Confirm the Vault address is the internal service URL, not the external route

### Image pull fails (disconnected environment)
- Mirror `python:3.11-slim` to your internal registry
- Update the `image:` field in the Task to point to `your-registry.example.com/python:3.11-slim`
- Ensure the namespace's pull secret has access to that registry

---

## What to Change Per Environment

When deploying to a new cluster you only need to update three files:

| File | What to change |
|---|---|
| `pipeline-config.yaml` | `keycloak-url`, `vault-address` — point at your cluster's internal services |
| `pipeline-env-secret.yaml` | Keycloak admin username and password |
| `vault-token-secret.yaml` | Vault token |

The Task script and Pipeline YAML need no changes.

---

## File Summary

| File | Purpose |
|---|---|
| `pipeline-config.yaml` | ConfigMap — URLs and path names |
| `pipeline-env-secret.yaml` | Secret — Keycloak admin credentials |
| `vault-token-secret.yaml` | Secret — Vault token |
| `keycloak-vault-sync-task.yaml` | Tekton Task — all the logic |
| `keycloak-vault-sync-pipeline.yaml` | Tekton Pipeline — param wiring |
