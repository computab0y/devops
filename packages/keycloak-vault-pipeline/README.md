# keycloak-vault-sync Pipeline

Reads users from a Keycloak realm (filtered by OU attribute) and syncs their usernames and passwords into HashiCorp Vault. Also updates the username dropdown in the companion `ftp-file-pipeline` if it is deployed in the same namespace.

## Prerequisites

- OpenShift Pipelines operator installed
- HashiCorp Vault running with KV v2 enabled at the configured path
- Keycloak running and accessible from cluster pods
- `oc` CLI logged in to the target cluster

## Step 1 — Edit pipeline-config.yaml

```yaml
keycloak-url:       "http://keycloak-service.keycloak.svc:8080"  # Internal Keycloak URL
vault-address:      "http://vault.vault.svc:8200"                 # Internal Vault URL
vault-secret-users: "ftp-users"                                   # Vault KV path
```

## Step 2 — Edit pipeline-env-secret.yaml

Replace `REPLACE_ME` with your Keycloak admin credentials:

```yaml
keycloak-admin-username: "your-admin-user"
keycloak-admin-password: "your-admin-password"
```

## Step 3 — Edit vault-token-secret.yaml

Replace `REPLACE_ME` with a Vault token that has KV read/write access on the `vault-secret-users` path.

## Step 4 — Deploy

```bash
chmod +x deploy.sh
./deploy.sh
```

Custom namespace:
```bash
./deploy.sh my-namespace
```

## Usage

**OCP Console:** Pipelines → `keycloak-vault-sync` → Start

You will be prompted for three parameters before the pipeline runs:

| Parameter | Default | Description |
|---|---|---|
| `target-ou` | `FTP-Users` | Keycloak user attribute value to filter on |
| `keycloak-realm` | `rgb-realm` | Keycloak realm to sync from |
| `vault-address` | `http://vault.vault.svc:8200` | Vault server address |

**CLI:**
```bash
# Run with defaults
tkn pipeline start keycloak-vault-sync -n openshift-pipelines-operator

# Override realm and OU
tkn pipeline start keycloak-vault-sync \
  -p keycloak-realm=my-realm \
  -p target-ou=MyGroup \
  -p vault-address=http://vault.vault.svc:8200 \
  -n openshift-pipelines-operator
```

## Files

| File | Purpose |
|---|---|
| `pipeline-config.yaml` | ConfigMap — Keycloak URL, Vault address, secret path |
| `pipeline-env-secret.yaml` | Secret — Keycloak admin credentials |
| `vault-token-secret.yaml` | Secret — Vault authentication token |
| `keycloak-vault-sync-task.yaml` | Tekton Task |
| `keycloak-vault-sync-pipeline.yaml` | Tekton Pipeline |
| `deploy.sh` | Deployment script |
