# Artifactory → DockerHub Credential Sync Pipeline

This pipeline was built to clear the "set a DockerHub account on your Docker remote
repositories" admin notice by writing DockerHub credentials into the `docker-remote` and
`oci-remote` remote repository configs via the Artifactory REST API. Credentials are
stored in Vault, not in git — the pipeline reads them at run time the same way
`keycloak-vault-sync` does.

> **Known limitation — confirmed 2026-09-13:** the Artifactory Repository Configuration
> REST API (`GET`/`POST /api/repositories/{repoKey}`) that this Task calls is gated behind
> an **Artifactory Pro/Enterprise license**. Against the free **Artifactory OSS / JFrog
> Container Registry** edition it always fails with:
> ```
> HTTP Error 400: Bad Request
> {"errors":[{"status":400,"message":"This REST API is available only in Artifactory Pro
> (see: jfrog.com/artifactory/features)..."}]}
> ```
> There is no scripted workaround — this endpoint simply doesn't exist on the free edition.
> The `artifactory-dockerhub-sync-trigger` CronJob is **suspended** (`spec.suspend: true`)
> until this cluster's Artifactory is licensed for Pro. Until then, clear the notice with
> the one-time manual fix below instead — the Task/Pipeline/CronJob are kept in git in case
> of a future Pro upgrade.

## Manual fix (works on any edition, including OSS)

For each repo in the notice (`docker-remote`, `oci-remote`):

1. Artifactory UI → **Administration → Repositories → Remote** → click the repo.
2. On the **Basic** tab, fill in **User Name** and **Password / Access Token** with your
   DockerHub username and a DockerHub Personal Access Token (not your DockerHub password —
   see Prerequisites below).
3. Click **Save**.

Repeat for the other repo. The admin notice banner clears immediately once both are saved
(no page-cache delay observed in practice).

```
OCP Console / tkn CLI
        │
        ▼
  Tekton Pipeline  ──► Task (python:3.11-slim container)
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
              HashiCorp Vault      Artifactory REST API
           (read DockerHub creds)  (GET + POST repo config)
```

## Prerequisites

| Requirement | Notes |
|---|---|
| `vault-token` Secret | Already deployed by `ftp-pipeline` — reused here |
| DockerHub account | A free/paid DockerHub account; generate a Personal Access Token (DockerHub → Account Settings → Security → Personal Access Tokens) rather than using your DockerHub password |
| Artifactory admin/service user | Needs permission to update repository configuration |
| Artifactory access token | Generate under Administration → Access Tokens (or your user profile's Identity Token on newer versions) — do not use the account password |

## Step 1 — Seed Vault with your DockerHub credentials

From a pod/route that can reach Vault (or `oc rsh` into any pod in the `vault` namespace):

```bash
curl -s -X POST \
  -H "X-Vault-Token: root" \
  -d '{"data": {"username": "<dockerhub-username>", "token": "<dockerhub-pat>"}}' \
  http://vault.vault.svc:8200/v1/secret/data/dockerhub
```

(`root` is the same dev-mode token already used by `vault-token`. If Vault is unsealed with
a real root/periodic token in your environment, use that instead.)

## Step 2 — Set your Artifactory credentials

Edit `pipeline-config.yaml` in this directory:
- Replace the two `CHANGE_ME` values in the `artifactory-pipeline-env` Secret with your
  Artifactory username and access token.
- Replace `artifactory-url` in the `artifactory-pipeline-config` ConfigMap with your real
  Artifactory URL — this is what the scheduled CronJob run uses (a manual `tkn`/console
  start can still override it per-run).

Then apply:

```bash
oc apply -k operators/subscription/tekton/base
```

This also creates the `artifactory-pipeline-config` ConfigMap, the
`artifactory-dockerhub-sync` Task, and the `artifactory-dockerhub-sync` Pipeline.

## Step 3 — Run it

From the OCP console: Pipelines → `artifactory-dockerhub-sync` → Start, and fill in
`artifactory-url` (e.g. `http://artifactory.artifactory.svc:8082` if calling it in-cluster,
or its external route if not) — `repo-keys` defaults to `docker-remote,oci-remote`.

Or via `tkn`:

```bash
tkn pipeline start artifactory-dockerhub-sync \
  -n openshift-pipelines-operator \
  -p artifactory-url=http://artifactory.artifactory.svc:8082 \
  -p repo-keys=docker-remote,oci-remote \
  --showlog
```

Re-run any time you rotate the DockerHub token in Vault — just repeat Step 1 and start the
pipeline again; nothing else needs to change.

## Step 4 — Automatic re-sync (optional)

A CronJob (`artifactory-dockerhub-sync-trigger`, weekly on Sundays at 03:00 by default) starts the
pipeline for you using the `artifactory-url` / `repo-keys` values from the ConfigMap — useful if you
rotate the DockerHub token in Vault periodically and want it picked up without manually starting a run.
It reuses the existing `pipeline` ServiceAccount, same as the `daily-health-check-trigger` CronJob.

Change the schedule by editing `cronjob.yaml`'s `spec.schedule` (standard cron syntax, UTC). To trigger
a sync immediately without waiting for the schedule:

```bash
oc create job --from=cronjob/artifactory-dockerhub-sync-trigger artifactory-dockerhub-sync-manual -n openshift-pipelines-operator
```

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `ERROR: Vault secret 'secret/dockerhub' must contain 'username' and 'token' fields` | Step 1 wasn't run, or ran against the wrong Vault address |
| `ERROR: Failed to fetch repo config for 'docker-remote'` | `artifactory-url` is wrong, unreachable from the pipelines namespace, or the repo key doesn't exist |
| `401`/`403` in the task log | `artifactory-username` / `artifactory-token` in `artifactory-pipeline-env` are wrong or lack permission to edit repository configuration |
| `"This REST API is available only in Artifactory Pro"` | Your Artifactory edition is OSS/JFrog Container Registry, not Pro — this pipeline's API calls can't work; use the manual fix above instead |
| Admin notice banner still shows after fixing both repos | Reload the page; if it still shows, double check both `docker-remote` and `oci-remote` were saved (not just one) |
