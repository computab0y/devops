# devops

Infrastructure, operator subscriptions, Tekton pipelines, and deployment packages for OpenShift clusters.

---

## Repo Structure

```
devops/
├── cluster-bootstrap/                # CatalogSources (redhat-operators, certified-operators)
│   ├── catalogsources.yaml
│   └── kustomization.yaml
│
├── docs/                             # Guides and documentation
│   ├── keycloak-vault-sync-guide.md  # Step-by-step guide to build the Keycloak→Vault pipeline
│   └── artifactory-dockerhub-sync-guide.md  # Step-by-step guide to build the Artifactory→DockerHub sync pipeline
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
│       │       ├── artifactory-pipeline/  # Artifactory→DockerHub credential sync pipeline
│       │       │   ├── task.yaml                   # artifactory-dockerhub-sync Task
│       │       │   ├── pipeline.yaml               # artifactory-dockerhub-sync Pipeline
│       │       │   ├── pipeline-config.yaml        # ConfigMap + Secret
│       │       │   └── cronjob.yaml                # Weekly auto re-sync trigger
│       │       └── health-check/     # Cluster health check pipeline
│       ├── test-app/                 # Mock trading API, Swagger UI, mock FTP server
│       ├── artifactory-pullthrough-test/  # Proof that images pull through Artifactory's docker-remote
│       └── vault/                    # HashiCorp Vault deployment
│
├── packages/                         # Standalone deployment packages
│   ├── keycloak-vault-pipeline/      # Keycloak→Vault sync pipeline package
│   ├── keycloak-vault-pipeline.tar.gz
│   ├── ftp-file-pipeline/            # FTP operations pipeline package
│   ├── ftp-file-pipeline.tar.gz
│   ├── must-gather-pipeline/         # Sanitised must-gather → canary check → Artifactory
│   ├── must-gather-pipeline.tar.gz
│   ├── must-gather-pipeline-disconnected/  # Air-gapped: pick cluster + type, image found in Artifactory
│   └── must-gather-pipeline-disconnected.tar.gz
│
├── terraform/                        # Terraform infrastructure configs
│   ├── main.tf                       # Local CRC cluster bootstrap (Mac track)
│   └── contabo-okd/                  # Contabo VPS + Cloudflare DNS (production track)
│
└── ansible/
    ├── playbook.yml                  # Local CRC cluster bootstrap (Mac track)
    ├── vars.yml
    └── contabo-okd/                  # Full day-2 config for the Contabo cluster (production track)
```

---

## Pipelines

Three Tekton pipelines are deployed in the `openshift-pipelines-operator` namespace.
Run `keycloak-vault-sync` first — it populates Vault and the username dropdown for `ftp-file-pipeline`.
`artifactory-dockerhub-sync` is independent of the other two.

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

### artifactory-dockerhub-sync

Reads DockerHub credentials from Vault and writes them into the Artifactory `docker-remote` / `oci-remote`
remote repository configs, clearing the "set a DockerHub account" admin notice.

**⚠️ Currently non-functional on Artifactory OSS / JFrog Container Registry:** the
Artifactory Repository Configuration REST API this Task calls is Pro/Enterprise-licensed
only — confirmed by a real run against this cluster's Artifactory on 2026-09-13
(`HTTP 400: "This REST API is available only in Artifactory Pro"`). The
`artifactory-dockerhub-sync-trigger` CronJob is suspended as a result. The admin notice
was cleared by hand instead — see `docs/artifactory-dockerhub-sync-guide.md` for the manual
steps and full background. This pipeline is left in place in case Artifactory is ever
licensed for Pro.

| | |
|---|---|
| Source | `operators/subscription/tekton/base/artifactory-pipeline/task.yaml` |
| Namespace | `openshift-pipelines-operator` |
| Vault path | `secret/dockerhub` |

**Start parameters:**

| Parameter | Default | Description |
|---|---|---|
| `artifactory-url` | _(required)_ | Base URL of the Artifactory instance |
| `repo-keys` | `docker-remote,oci-remote` | Comma-separated remote repository keys to update |
| `vault-address` | `http://vault.vault.svc:8200` | Vault server address |

```bash
tkn pipeline start artifactory-dockerhub-sync -p artifactory-url=http://artifactory.artifactory.svc:8082 -n openshift-pipelines-operator
```

A weekly CronJob (`artifactory-dockerhub-sync-trigger`, currently suspended — see above)
would otherwise re-run this automatically — see `docs/artifactory-dockerhub-sync-guide.md`
for full setup, including seeding Vault with DockerHub credentials and generating an
Artifactory access token.

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

## Production track: Contabo-hosted OKD (`terraform/contabo-okd` + `ansible/contabo-okd`)

Everything above (kustomize bases in `operators/subscription/*`, the `terraform/main.tf`
+ `ansible/playbook.yml` at the repo root) targets a **local CRC cluster** on a Mac -
CRC-specific bits like `apps-crc.testing` hostnames show up throughout the bases as a
result.

This repo also runs on a real, publicly-reachable single-node OKD cluster on a Contabo
VPS (`*.apps.okd.funky-bash.com`), used as the "always-on" instance rather than the local
CRC one. Two directories support that specific deployment:

- **`terraform/contabo-okd/`** - manages the Contabo compute instance (size/plan) and the
  Cloudflare DNS records pointing at it. See its README for the VPS resize workflow
  (Contabo doesn't support in-place resize via API/Terraform - it's a manual "Live
  Migration" step in the Customer Control Panel, with Terraform reconciling state
  afterward).
- **`ansible/contabo-okd/`** - repeatable day-2 configuration: pull secret, operator
  catalogs, all 17 real operator Subscriptions, and every operand (Vault,
  external-secrets, Grafana + monitoring stack, Keycloak SSO + realm, Tekton pipelines).
  Applies every `operators/subscription/*` kustomization straight from this GitHub repo
  via `oc apply -k https://github.com/...`, so it always deploys whatever's currently
  committed here.

Where the two tracks share `operators/subscription/*` bases, `overlay/env/` is the
Contabo/production overlay - it patches the CRC-specific hostnames
(`apps-crc.testing`) to the real cluster domain (`apps.okd.funky-bash.com`) via
`sso/overlay/env/*-patch.yaml`. A handful of bugs found while deploying this for real
were also fixed directly in the base manifests (they were bugs regardless of
environment): channel/version drift in `oadp`, `edb-postgresql`, and `external-secrets`'
Subscriptions; `otel/base/subscription.yaml` was a hand-vendored, unresolvable
ClusterServiceVersion rather than an actual Subscription; `external-secrets/base`
assumed CRD versions and a Red-Hat-specific `ExternalSecretsConfig` CRD that don't exist
for the community operator that actually installs; `sso/base` referenced legacy
`keycloak.org/v1alpha1` CRDs that keycloak-operator v26.6.4 no longer ships (superseded
by the `k8s.keycloak.org/v2alpha1` `KeycloakRealmImport` resource, which is what's
actually used); `vault/base/deployment.yaml` now bakes in the `-dev-no-store-token` flag
Vault's dev-mode needs under OpenShift's restricted SCC.

`edb-postgresql` remains genuinely blocked regardless of environment - its manager image
is pulled from EnterpriseDB's own registry, requiring separate credentials this
deployment doesn't have (documented in `operators/subscription/edb-postgresql/base/subscription.yaml`).

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
