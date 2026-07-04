# ftp-file-pipeline

Connects to an FTP server as a Vault-managed user and performs file operations (list, create, delete) in the SUBMISSION or NOTIFICATION folders.

## Dependency

**Run `keycloak-vault-sync` first.** This pipeline reads user credentials from Vault. The sync pipeline must run before this one to populate Vault with credentials and update the username dropdown.

## Prerequisites

- OpenShift Pipelines operator installed
- HashiCorp Vault running with user credentials already synced by `keycloak-vault-sync`
- FTP server reachable from cluster pods
- SSH root access to the FTP server VM (for user provisioning)
- `oc` CLI logged in to the target cluster

## Step 1 — Edit pipeline-config.yaml

```yaml
ftp-host:           "your-ftp-server-ip"           # FTP server hostname or IP
ftp-port:           "21"                             # FTP port (usually 21)
vault-address:      "http://vault.vault.svc:8200"   # Internal Vault URL
vault-secret-users: "ftp-users"                     # Must match keycloak-vault-sync config
```

## Step 2 — Edit vault-token-secret.yaml

Replace `REPLACE_ME` with a Vault token that has KV read access on the `vault-secret-users` path.

## Step 3 — Edit ftp-vm-ssh-key-secret.yaml

Generate an SSH key pair and authorise it on the FTP server VM:

```bash
ssh-keygen -t rsa -b 4096 -f ftp-vm-key -N ""
ssh root@<ftp-host> "cat >> ~/.ssh/authorized_keys" < ftp-vm-key.pub
cat ftp-vm-key | base64 -w 0   # paste the output into ftp-vm-ssh-key-secret.yaml as id_rsa
```

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

**OCP Console:** Pipelines → `ftp-file-pipeline` → Start

| Parameter | Options | Description |
|---|---|---|
| `username` | dropdown (populated by sync) | FTP user to connect as |
| `action` | `list-files`, `create-file`, `delete-file` | Operation to perform |
| `target-folder` | `SUBMISSION`, `NOTIFICATION` | Target folder on the FTP server |
| `file-name` | string | Required for create and delete; leave blank for list |

**CLI:**
```bash
# List files in both folders
tkn pipeline start ftp-file-pipeline \
  -p username=testuser1 \
  -p action=list-files \
  -p target-folder=SUBMISSION \
  -n openshift-pipelines-operator

# Create a file
tkn pipeline start ftp-file-pipeline \
  -p username=testuser1 \
  -p action=create-file \
  -p target-folder=SUBMISSION \
  -p file-name=myfile.txt \
  -n openshift-pipelines-operator

# Delete a file
tkn pipeline start ftp-file-pipeline \
  -p username=testuser1 \
  -p action=delete-file \
  -p target-folder=SUBMISSION \
  -p file-name=myfile.txt \
  -n openshift-pipelines-operator
```

## Files

| File | Purpose |
|---|---|
| `pipeline-config.yaml` | ConfigMap — FTP host/port and Vault config |
| `vault-token-secret.yaml` | Secret — Vault authentication token |
| `ftp-vm-ssh-key-secret.yaml` | Secret — SSH private key for FTP VM user provisioning |
| `ftp-operations-task.yaml` | Tekton Task — FTP logic |
| `ftp-file-pipeline.yaml` | Tekton Pipeline |
| `deploy.sh` | Deployment script |
