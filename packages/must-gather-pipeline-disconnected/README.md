# Sanitised must-gather pipeline — disconnected edition

A Tekton pipeline for air-gapped OpenShift environments where every image lives in
Artifactory. You pick **which cluster** and **which type of must-gather**; the pipeline
then:

1. works out the version to match from the **target cluster** (cluster version, or the
   version of the operator being gathered),
2. **searches Artifactory** for the matching must-gather image and pins it by digest,
3. runs `oc adm must-gather` on the target cluster with that image,
4. sanitises the output with **must-gather-clean**, using that cluster's own config,
5. **fails the run** if any known-sensitive string ("canary") survived,
6. packages the result and **uploads it to Artifactory**.

```
                 pipeline cluster (OpenShift Pipelines)                         Artifactory
 you ──start──▶  resolve-image ──search (Docker v2 API)──────────────────────▶ docker repo
 (cluster,        │  reads target version via kubeconfig ──▶ target cluster        ▲
  type)           ▼                                              │ nodes pull      │
                 gather ── oc adm must-gather ─────────────────▶ │ must-gather ────┘
                  ▼          (output streamed back)               ▼ image
                 sanitise ─▶ canary-check ─▶ package ─▶ upload ──────────────▶ generic repo
                 finally: cleanup-target · purge-raw-on-failure · retention
```

Nothing in the pipeline, the image build or the image search needs internet access.

---

## Step 1 — What you need

| Where | What |
|---|---|
| **Pipeline cluster** | OpenShift with the **OpenShift Pipelines** operator installed (from your mirrored catalog) and a default StorageClass. The pipeline cluster can also be one of the targets. |
| **Artifactory** | a **Docker** repository for images (e.g. `docker-local`), a **Generic** repository for archives (e.g. `generic-local`), and a user that can **read** the Docker repo and **deploy** to the Generic repo. JFrog Container Registry is enough: only the standard Docker v2 API is used. |
| **Network** | pipeline pods → Artifactory API; pipeline pods → each target cluster's API (port 6443); target cluster nodes → Artifactory registry. |
| **Target clusters** | Artifactory in the **global pull secret** and, if Artifactory's certificate isn't publicly trusted, its CA trusted for image pulls — see *Target cluster prerequisites*. Disconnected clusters normally have both already. |
| **Workstation** | `oc`, `bash`, `python3`; `podman` (or a build host) for step 3; a connected machine or bastion for step 2. |

## Step 2 — Mirror the images into Artifactory

The pipeline needs, in the Docker repo:
- the **must-gather images** for every type and version you want to run,
- a **CLI image** with `oc` and `bash` (e.g. `openshift4/ose-cli-rhel9`),
- a **UBI 9 base image** for building must-gather-clean (step 3).

1. Copy `mirror-list.example.txt` to `local/mirror-list.txt`; list one line per image
   **and version** you need — e.g. one must-gather per OCP minor across your clusters, and
   one per installed operator version:
   ```
   registry.redhat.io/rhacm2/acm-must-gather-rhel9:v2.13   rhacm2/acm-must-gather-rhel9:v2.13
   ```
   The right-hand side is the path **inside the Docker repo**. Two rules make the search work:
   - the path must **end with** the image name in the catalogue (step 4) — any prefix is fine;
   - the **tag must carry the version**: `v2.13`, `2.13`, `v2.13.1` or `2.13.1`.

   See which tags exist upstream with `skopeo list-tags docker://registry.redhat.io/<repo>`.
2. Build an auth file holding `registry.redhat.io` and your Artifactory:
   ```bash
   export REGISTRY_AUTH_FILE=$PWD/local/auth.json
   podman login --authfile $REGISTRY_AUTH_FILE registry.redhat.io
   podman login --authfile $REGISTRY_AUTH_FILE artifactory.example.com
   ```
3. Mirror — pick the mode that fits your air gap:
   ```bash
   # bastion that reaches both the internet and Artifactory
   scripts/mirror-images.sh direct    local/mirror-list.txt artifactory.example.com/docker-local
   # fully air-gapped: to disk on the connected side ...
   scripts/mirror-images.sh to-disk   local/mirror-list.txt /media/usb/mg
   # ... carry the directory across, then on the disconnected side
   scripts/mirror-images.sh from-disk local/mirror-list.txt /media/usb/mg artifactory.example.com/docker-local
   ```
   (If you already mirror with `oc-mirror`, add these images under `additionalImages` in
   your ImageSetConfiguration instead — just keep the path and tag rules above.)

## Step 3 — Build the must-gather-clean image

On a connected machine, download the release and check it:
```bash
cd image
curl -LO https://github.com/openshift/must-gather-clean/releases/download/v0.0.5/must-gather-clean-linux-amd64.tar.gz
curl -LO https://github.com/openshift/must-gather-clean/releases/download/v0.0.5/SHA256_SUM
awk '$2=="must-gather-clean-linux-amd64.tar.gz" {print $1"  "$2}' SHA256_SUM | sha256sum -c -        # tarball
tar xzf must-gather-clean-linux-amd64.tar.gz must-gather-clean
awk '$2=="must-gather-clean-linux-amd64" {print $1"  must-gather-clean"}' SHA256_SUM | sha256sum -c -  # binary
```
(`SHA256_SUM` uses a single space and lists the extracted binary as
`must-gather-clean-linux-amd64`, hence the `awk`. On macOS use `shasum -a 256 -c -`.)
Carry `image/` across if needed, then build **from the UBI image in Artifactory** and push:
```bash
podman build --build-arg BASE_IMAGE=artifactory.example.com/docker-local/ubi9/ubi:latest \
  -t artifactory.example.com/docker-local/tools/must-gather-clean:v0.0.5 image/
podman push artifactory.example.com/docker-local/tools/must-gather-clean:v0.0.5
```
The build re-checks the binary against the pinned SHA-256 (`MGC_SHA256`, amd64 by
default; the Containerfile has the arm64 value) and fails if any tool the tasks need
(`bash curl python3 tar gzip sha256sum find`) is missing.

No podman? Build in-cluster with a Docker-strategy BuildConfig and
`oc start-build --from-dir=image` — the base image still comes from Artifactory.

## Step 4 — Configure

```bash
cp 03-settings.example.yaml local/03-settings.yaml
```
Edit `local/03-settings.yaml`:

| Key | Meaning |
|---|---|
| `ARTIFACTORY_URL` | Artifactory base URL **as the pipeline pods reach it**, e.g. `https://artifactory.example.com/artifactory` |
| `DOCKER_REPO` | Docker repo holding the images, e.g. `docker-local` |
| `REGISTRY_PREFIX` | how **target nodes** address that repo in a pull spec — depends on Artifactory's Docker access method: `artifactory.example.com/docker-local` (repository path), `docker-local.artifactory.example.com` (subdomain) or `artifactory.example.com:5001` (port) |
| `UPLOAD_PATH` | where archives go: `<ARTIFACTORY_URL>/<UPLOAD_PATH>/<cluster>/` |
| `CATALOG` | gather type → image name → version rule (below) |

The **catalogue** has one line per gather type:
```
acm   rhacm2/acm-must-gather-rhel9   operator:advanced-cluster-management
```
- **image name** — matched against the *end* of the repository paths in `DOCKER_REPO`;
  `name1|name2` tries each in turn.
- **version rule** — `cluster` (match the target's OCP version X.Y) or
  `operator:<CSV name prefix>` (match that operator's installed X.Y on the target).
- `default` is also the image used when `includeDefault=true`.

To add a type: add a catalogue line **and** add the type to the `gatherType` enum in
`tekton/pipeline.yaml`, then re-run `deploy.sh`.

## Step 5 — Deploy

Log `oc` in to the **pipeline cluster**, then:
```bash
export ARTIFACTORY_USERNAME=mg-pipeline ARTIFACTORY_PASSWORD='...'
export CLI_IMAGE=artifactory.example.com/docker-local/openshift4/ose-cli-rhel9:v4.18
export MGC_IMAGE=artifactory.example.com/docker-local/tools/must-gather-clean:v0.0.5
# only if Artifactory's certificate is signed by a private CA:
export ARTIFACTORY_CA_FILE=/path/to/corporate-ca.pem
./deploy.sh
```
It creates namespace `must-gather-pipelines` (override with `NAMESPACE=`), the task
service account, a 10Gi PVC, the settings ConfigMap, the Artifactory credentials (and CA)
and the Tasks and Pipeline. The pipeline cluster's own nodes must be able to pull
`CLI_IMAGE` and `MGC_IMAGE` from Artifactory.

## Step 6 — Add target clusters

For **each** cluster you want to gather from:

1. Log `oc` in to **that target cluster** as cluster-admin and run
   ```bash
   scripts/target-kubeconfig.sh prod-east https://api.prod-east.example.com:6443
   ```
   This creates, on the target, namespace `must-gather-access` with service account
   `must-gather-runner` (cluster-admin — `oc adm must-gather` needs it to create its
   temporary namespace and privileged gather pod) and a long-lived token, and writes
   `config/prod-east.kubeconfig`. Give the API URL **as the pipeline cluster reaches it**;
   for the pipeline cluster itself use `https://kubernetes.default.svc`. If the API uses a
   custom certificate, add `CA_FILE=/path/to/ca.pem`.
2. Write that cluster's sanitiser config and canaries (or use shared `config/default.*`):
   ```bash
   cp config/example.config.yaml  config/prod-east.config.yaml
   cp config/example.canaries.txt config/prod-east.canaries.txt
   ```
   Fill in its base domain, infrastructure name, node names, public IPs, usernames —
   anything that must not leave the site. **Every value you obfuscate should also be a
   canary**: that is what proves sanitising worked.
3. Log `oc` back in to the **pipeline cluster** and register it:
   ```bash
   scripts/add-cluster.sh prod-east
   ```
   It stores the kubeconfig and sanitiser config in Secrets and adds `prod-east` to the
   **targetCluster** dropdown. `config/` is gitignored — keep these files safe.

### Target cluster prerequisites

The target's nodes pull the must-gather image from Artifactory, so on each target:
- the **global pull secret** (`openshift-config/pull-secret`) has an entry for the
  registry host in `REGISTRY_PREFIX`;
- if Artifactory's certificate is from a private CA, that CA is trusted for image pulls:
  ```bash
  oc create configmap registry-cas -n openshift-config \
    --from-file=artifactory.example.com=/path/to/ca.pem      # key = registry host[..port]
  oc patch image.config.openshift.io/cluster --type merge \
    -p '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}'
  ```
Disconnected clusters usually have both already. If not, the gather task stops after
~2 minutes of `ImagePullBackOff` with a message saying so (instead of waiting out
must-gather's 50-minute timeout).

## Step 7 — Run it

**From the console:** Pipelines → `sanitised-must-gather` → **Start**:

| Field | Value |
|---|---|
| **targetCluster** | pick the cluster |
| **gatherType** | `default`, `acm`, `mce`, `logging`, `odf`, `oadp`, `gitops`, `cnv`, `servicemesh` |
| **includeDefault** | `true` = also run the standard cluster gather (what support usually wants) |
| imageTag | `auto` (match installed version) or an exact tag |
| since | how far back logs go, e.g. `24h` |
| upload | `true` |
| runId | leave `auto` |
| Service account (*Advanced*) | `must-gather-tasks` |
| `data` | PersistentVolumeClaim → `must-gather-data` |
| `kubeconfigs` | Secret → `mg-target-clusters` |
| `sanitise-config` | Secret → `mg-sanitise-config` |
| `settings` | ConfigMap → `mg-settings` |
| `artifactory-auth` | Secret → `artifactory-auth` |
| `ca-bundle` | ConfigMap → `artifactory-ca` (only if you set `ARTIFACTORY_CA_FILE`), otherwise leave empty |

**From the CLI** (sets all of the above):
```bash
scripts/start-run.sh prod-east acm              # cluster, type (includeDefault=true)
scripts/start-run.sh prod-east odf false        # ODF gather only
scripts/start-run.sh prod-east default true v4.18   # force a specific image tag
tkn pipelinerun logs -f -n must-gather-pipelines <name>
```

The first task shows what was found, e.g.
```
[target-versions] target 'prod-east': version 4.18.12, 64 operator CSVs
[search-artifactory] default: openshift4/ose-must-gather-rhel9:v4.18 (matches cluster version 4.18.12) -> artifactory.example.com/docker-local/openshift4/ose-must-gather-rhel9@sha256:…
[search-artifactory] acm: rhacm2/acm-must-gather-rhel9:v2.13 (matches advanced-cluster-management 2.13.2) -> …@sha256:…
```

## Step 8 — Get the result

```bash
tkn pipelinerun describe -n must-gather-pipelines <name>
```
shows `uploadUrl`, `archiveName`, `archiveSha256`, `canaryHits` (must be `0`),
`images` (exactly what ran) and `pvcUsage`. The archive —
`<cluster>-<runId>-<gatherType>-must-gather-sanitised.tar.gz` plus `.sha256` — is in
Artifactory at `<UPLOAD_PATH>/<cluster>/`. To copy one off the PVC instead:
`scripts/fetch-archive.sh <cluster> <runId>`.

`report/report.yaml` (original → replacement map) never leaves the PVC. Don't share it.

## Stopping a run

Cancel **with finally tasks**, so the temporary namespace on the target is removed:
```bash
oc patch pipelinerun <name> -n must-gather-pipelines --type merge -p '{"spec":{"status":"CancelledRunFinally"}}'
```
(`tkn pipelinerun cancel` skips finally tasks and can leave `openshift-must-gather-*`
behind on the target.)

## Troubleshooting

| Message | Fix |
|---|---|
| `no kubeconfig for cluster 'x'` | `scripts/add-cluster.sh x` (after `target-kubeconfig.sh`) |
| `operator … is not installed on the target cluster` | pick a type that is installed, or install it |
| `no image matching '…' in Artifactory repo` | mirror it (step 2); check the path ends with the catalogue name |
| `… has no tag for X.Y` | mirror that version, or set `imageTag` to one of the listed tags |
| `gatherType 'x' is not in the image catalogue` | add a `CATALOG` line (step 4) |
| `Artifactory refused the credentials (HTTP 401)` | fix Secret `artifactory-auth` (re-run `deploy.sh`) |
| `cannot reach Artifactory` / certificate errors | `ARTIFACTORY_URL` wrong, or set `ARTIFACTORY_CA_FILE` and re-run `deploy.sh` |
| `target cluster cannot pull the must-gather image` | *Target cluster prerequisites* |
| canary-check `FAIL` | a sensitive value survived — add it to that cluster's `config.yaml` obfuscation, re-run `add-cluster.sh`, run again |
| `InvalidParamValue` | a value outside a dropdown's list (CLI only) |

## Housekeeping

- **Retention:** every run ends by deleting earlier failed runs, stripping `clean/` and
  `raw/`, and keeping the newest `keepRuns` (default 3) runs per cluster on the PVC.
  Artifactory keeps everything.
- **New versions:** when a cluster or operator is upgraded, mirror the matching
  must-gather tag (step 2). Until then runs of that type fail with *has no tag for X.Y*.
- **Security:** the Artifactory user needs only read on the Docker repo and deploy on
  the upload path — don't use admin. Each target's `must-gather-runner` token is
  cluster-admin on that cluster; the kubeconfigs live only in Secret
  `mg-target-clusters` and your gitignored `config/`. To revoke a cluster, delete
  namespace `must-gather-access` and ClusterRoleBinding `must-gather-runner-cluster-admin`
  on it.

## How it differs from the connected version

| Connected | Disconnected |
|---|---|
| gathers from the cluster it runs on | **targetCluster** dropdown, any number of clusters |
| operator image from the CSV or Red Hat's registry | **searched in Artifactory**, tag matched to the installed version, pinned by digest |
| must-gather-clean image built from GitHub | built from a pre-downloaded, checksum-verified binary and a base image in Artifactory |
| one sanitiser config | one per cluster (`<cluster>.config.yaml`, fallback `default.*`) |
| Artifactory URL in params | all environment settings in ConfigMap `mg-settings` |
| — | fails fast on image pull errors; `cleanup-target` removes leftover namespaces |
