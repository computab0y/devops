# devops

Infrastructure, operator subscriptions, Tekton pipelines, and deployment packages for OpenShift clusters.

---

## Repo Structure

```
devops/
├── ansible/                          # Ansible playbooks
│   ├── playbook.yml                  # Main playbook
│   └── vars.yml                      # Variables
│
├── docs/                             # Guides and documentation
│   └── keycloak-vault-sync-guide.md  # Step-by-step guide to build the Keycloak→Vault pipeline
│
├── guacamole/                        # Apache Guacamole (remote desktop gateway)
│   ├── docker-compose.yml            # Full stack: Guacamole, guacd, PostgreSQL, nginx
│   ├── nginx.conf                    # Reverse proxy config
│   └── init/
│       ├── initdb.sql                # Guacamole database schema
│       └── totp-schema.sql           # TOTP extension schema
│
├── operators/
│   └── subscription/                 # OLM operator subscriptions (kustomize base/overlay)
│       ├── acs/                      # Advanced Cluster Security
│       ├── amq-streams/              # AMQ Streams (Kafka)
│       ├── devworkspaces/            # Dev Workspaces
│       ├── edb-postgresql/           # EDB PostgreSQL
│       ├── elasticsearch/            # Elasticsearch
│       ├── elasticsearch-eck-operator/
│       ├── external-secrets/         # External Secrets Operator
│       ├── gitops/                   # OpenShift GitOps (ArgoCD)
│       ├── tekton/                   # OpenShift Pipelines
│       │   └── base/
│       │       ├── ftp-pipeline/     # Keycloak→Vault sync + FTP operations pipelines
│       │       │   ├── task.yaml                   # keycloak-vault-sync Task
│       │       │   ├── pipeline.yaml               # keycloak-vault-sync Pipeline
│       │       │   ├── ftp-operations-task.yaml    # ftp-operations Task
│       │       │   ├── ftp-file-pipeline.yaml      # ftp-file-pipeline Pipeline
│       │       │   └── pipeline-config.yaml        # ConfigMap + Secret
│       │       └── health-check/     # Cluster health check pipeline
│       ├── test-app/                 # Mock trading API, Swagger UI, mock FTP server
│       └── vault/                    # HashiCorp Vault deployment
│
├── packages/                         # Standalone deployment packages
│   ├── keycloak-vault-pipeline/      # Keycloak→Vault sync pipeline package
│   ├── keycloak-vault-pipeline.tar.gz
│   ├── ftp-file-pipeline/            # FTP operations pipeline package
│   └── ftp-file-pipeline.tar.gz
│
└── terraform/                        # Terraform infrastructure configs
    └── main.tf
```

---

## Pipelines

Two Tekton pipelines are deployed in the `openshift-pipelines-operator` namespace.
Run `keycloak-vault-sync` first — it populates Vault and the username dropdown for `ftp-file-pipeline`.

### keycloak-vault-sync

Reads users from a Keycloak realm (filtered by OU attribute) and writes their credentials to HashiCorp Vault.

| | |
|---|---|
| Source | `operators/subscription/tekton/base/ftp-pipeline/task.yaml` |
| Namespace | `openshift-pipelines-operator` |
| Vault path | `secret/ftp-users` |

**Start parameters** (prompted in the OCP console Start screen):

| Parameter | Default | Description |
|---|---|---|
| `target-ou` | `FTP-Users` | Keycloak OU attribute to filter users by |
| `keycloak-realm` | `rgb-realm` | Keycloak realm to sync from |
| `vault-address` | `http://vault.vault.svc:8200` | Vault server address |

```bash
tkn pipeline start keycloak-vault-sync -n openshift-pipelines-operator
```

### ftp-file-pipeline

Connects to an FTP server as a Vault-managed user and performs file operations.

| | |
|---|---|
| Source | `operators/subscription/tekton/base/ftp-pipeline/ftp-file-pipeline.yaml` |
| Namespace | `openshift-pipelines-operator` |

**Start parameters:**

| Parameter | Options | Description |
|---|---|---|
| `username` | dropdown | FTP user — populated by keycloak-vault-sync |
| `action` | `list-files`, `create-file`, `delete-file` | Operation to perform |
| `target-folder` | `SUBMISSION`, `NOTIFICATION` | Target folder |
| `file-name` | string | Required for create and delete |

```bash
tkn pipeline start ftp-file-pipeline -p username=myuser -p action=list-files -p target-folder=SUBMISSION -n openshift-pipelines-operator
```

---

## Deployment Packages

The `packages/` directory contains standalone packages for deploying each pipeline to a new cluster.
Each package includes a `deploy.sh` script, all required YAMLs, and `REPLACE_ME` placeholders for secrets.

### Deploy to a new cluster

```bash
# 1. Edit config and secrets
vi packages/keycloak-vault-pipeline/pipeline-config.yaml
vi packages/keycloak-vault-pipeline/pipeline-env-secret.yaml
vi packages/keycloak-vault-pipeline/vault-token-secret.yaml

# 2. Run deploy script (optionally pass a namespace)
chmod +x packages/keycloak-vault-pipeline/deploy.sh
packages/keycloak-vault-pipeline/deploy.sh my-namespace
```

Repeat for `packages/ftp-file-pipeline/` — see each package's `README.md` for full instructions.

> See `docs/keycloak-vault-sync-guide.md` for a complete step-by-step guide to building
> the Keycloak→Vault pipeline from scratch on a new cluster.

---

## Guacamole

Apache Guacamole remote desktop gateway with PostgreSQL backend, TOTP authentication, and nginx reverse proxy.

```bash
cd guacamole
cp .env.example .env    # fill in passwords
docker-compose up -d
```

---

## Operators

Operator subscriptions are structured using kustomize `base/overlay` pattern.
Apply a specific operator:

```bash
oc apply -k operators/subscription/tekton/base
```

Apply with an environment overlay:

```bash
oc apply -k operators/subscription/tekton/overlay/env
```
