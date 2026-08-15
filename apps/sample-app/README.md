# sample-app

Minimal status service that exercises the full pipeline: GitHub → Tekton →
ArgoCD → Vault → Grafana.

| Endpoint | Description |
|---|---|
| `/` | HTML status page — shows version and whether the Vault-sourced credential loaded |
| `/healthz` | Liveness/readiness probe target |
| `/api/status` | JSON status: `app`, `version`, `vault_secret_loaded`, `time` |

Stdlib-only Python (no dependencies), consistent with the rest of this repo's apps.

## How the pieces connect

1. **GitHub** — source lives here, under `apps/sample-app/`. Manifests live in
   `operators/subscription/sample-app/base/`.
2. **Tekton** (`operators/subscription/sample-app/base/pipeline/`) — the
   `sample-app-ci` Pipeline clones the repo, builds `apps/sample-app/Dockerfile`
   with buildah, pushes it to the OpenShift internal registry, then commits the
   new image tag into `operators/subscription/sample-app/base/deployment.yaml`
   and pushes that commit back to `main`.
3. **ArgoCD** (`argocd/sample-app-application.yaml`) — watches
   `operators/subscription/sample-app/base` on `main` with automated
   `prune`+`selfHeal`. It picks up the commit from step 2 and syncs the new
   image to the cluster. Tekton never touches the cluster directly — it only
   builds and updates git; ArgoCD is the only thing that applies to the cluster.
4. **Vault** — two credentials, both delivered via the existing
   `vault-backend` `ClusterSecretStore` (External Secrets Operator):
   - `secret/sample-app` → `greeting` — the app's own runtime credential,
     injected as the `GREETING` env var. The app never logs or echoes the
     value; `/api/status` only reports whether it loaded.
   - `secret/sample-app-pipeline` → `github-username` / `github-token` — the
     token the pipeline uses to push the manifest update back to GitHub.
5. **Grafana** — the existing "Comprehensive Cluster Health & Inventory"
   dashboard (`operators/subscription/grafana/base/grafana-dashboard.yaml`)
   already templates on `namespace` via
   `label_values(kube_pod_info, namespace)`, so `sample-app` shows up in its
   namespace dropdown automatically once deployed — no dashboard change
   needed. Open it at the cluster's Grafana route and pick `sample-app`:
   ```bash
   oc get route grafana -n grafana-operator -o jsonpath='{.spec.host}'
   ```

## One-time setup

Seed the two Vault secrets this app and pipeline need (dev-mode Vault, root
token, matches the pattern the `keycloak-vault-sync` pipeline already uses):

```bash
export VAULT_ADDR=http://$(oc get route vault -n vault -o jsonpath='{.spec.host}')
export VAULT_TOKEN=root

vault kv put secret/sample-app greeting="Hello from Vault!"
vault kv put secret/sample-app-pipeline \
  github-username=<your-github-username> \
  github-token=<a GitHub PAT with repo push access>
```

Apply the app + pipeline manifests once, then hand ownership to ArgoCD:

```bash
oc apply -k operators/subscription/sample-app/base   # first apply, bootstraps the namespace
oc apply -f argocd/sample-app-application.yaml       # ArgoCD takes over from here
```

## Running the pipeline

```bash
tkn pipeline start sample-app-ci -n sample-app \
  --workspace name=source,claimName=sample-app-source-pvc,accessMode=ReadWriteOnce,size=1Gi \
  --workspace name=git-credentials,secret=sample-app-git-credentials \
  --use-param-defaults
```

or `oc create -f operators/subscription/sample-app/base/pipeline/pipelinerun.yaml`.
