# Sanitised must-gather pipeline

A Tekton pipeline that collects an OpenShift/OKD `must-gather`, strips sensitive data
out of it with [must-gather-clean](https://github.com/openshift/must-gather-clean),
**proves** the strip worked by checking for known sensitive strings ("canaries"),
packages the result, and uploads it to Artifactory.

```
 gather ──> sanitise ──> canary-check ──> package ──> upload (if upload=true)
                                                          finally: retention (keep newest keepRuns)
   │           │              │               │
   raw/      clean/        fails run       tar.gz + sha256,
             report/       on any hit      raw/ purged
                                                          finally: purge raw/ if anything failed
```

## Files

| Path | What |
|---|---|
| `00-namespace.yaml` | `must-gather-pipelines` namespace (PSA audit/warn = restricted) |
| `01-rbac.yaml` | `must-gather-runner` SA + cluster-admin + token Secret (identity used by `oc adm must-gather`); `must-gather-tasks` SA (identity the task pods run as - no grants, so `restricted-v2`) |
| `02-pvc.yaml` | 10Gi `must-gather-data` PVC on the default StorageClass |
| `03-build.yaml` + `image/Containerfile` | BuildConfig building the must-gather-clean image into the internal registry |
| `04-scheduler.yaml` | daily CronJob that starts runs as SA `must-gather-scheduler` (can only create/list PipelineRuns here) |
| `tekton/tasks.yaml` | the seven Tasks |
| `tekton/pipeline.yaml` | the Pipeline |
| `tekton/pipelinerun-template.yaml` | run template used by `scripts/start-run.sh` |
| `scripts/create-kubeconfig-secret.sh` | builds the `must-gather-kubeconfig` Secret from the runner token |
| `scripts/start-run.sh` | starts a run with a fresh `runId` |
| `scripts/fetch-archive.sh` | copies a run's tarball off the PVC and verifies its checksum |
| `config/*.example.*` | templates for `config/mgc-config.yaml` + `config/canaries.txt` (gitignored: they list exactly what you're hiding) |
| `deploy.sh` | one-shot install: manifests, image build, Secrets, Tasks, Pipeline |

## How each stage works

**gather** (`quay.io/openshift/origin-cli:4.22`) - works out which must-gather image(s) to
run from `gatherType` (see *Choosing the type of must-gather*), then runs `oc adm must-gather --since=24h`
using the kubeconfig Secret (SA `must-gather-runner`, cluster-admin, API
`https://kubernetes.default.svc`). must-gather spins up a temporary
`openshift-must-gather-*` namespace with a privileged gather pod - that's why the
*runner* identity needs cluster-admin while the *task* pod itself stays restricted.
The task then waits up to 3 min for that namespace to disappear and records whether
it did. The must-gather console output (node names, IPs...) goes to
`report/must-gather.log` on the PVC, not to the step log, because OpenShift Pipelines
keeps step logs in Tekton Results.

**sanitise** (must-gather-clean image) - `must-gather-clean -c config.yaml -i raw -o clean -r report`.
The config (Secret `mgc-config`, key `config.yaml`):
- obfuscates **IPs, MACs** (consistent replacements, in file contents *and* paths),
- **domains**: the cluster base domain and its parents/subdomains, plus the node's
  provider-assigned FQDN,
- **keywords**: the cluster infrastructure name, the node/VPS hostname, usernames -
  anything else you don't want to leave the building,
- **omits** Secrets, ConfigMaps, CSRs, MachineConfigs and symlinks entirely.

`report/report.yaml` maps every original to its replacement - it stays on the PVC and
is never printed, packaged or uploaded. stdin is redirected from `/dev/null`: with a
non-terminal stdin must-gather-clean otherwise waits for piped input forever.

**canary-check** - reads Secret `mgc-config` key `canaries.txt` (one literal per line),
adds the dash form of any IPv4 (`203-0-113-10`, how IPs appear in hostnames), then
searches `clean/` case-insensitively in file contents, file/directory names and inside
`.gz` files. Any hit fails the run before anything is packaged. Only counts are
printed, never the matching text.

**package** - `tar czf <alias>-<runId>-<gatherType>-must-gather-sanitised.tar.gz clean/` + a
`.sha256`, reads the tarball back, deletes `clean/` and `raw/`, and verifies `raw/` is gone and `report/report.yaml` is
still there.

**upload** (default on; `upload=false` skips it) - PUTs the tarball and `.sha256` to
`<artifactoryUrl>/<alias>/`, by default
`http://artifactory.artifactory.svc:8082/artifactory/generic-local/must-gather/<alias>/`
using Secret `artifactory-auth` (`username`/`password`; `deploy.sh` creates it from
`ARTIFACTORY_USERNAME`/`ARTIFACTORY_PASSWORD` - use a user that can only deploy to the
target repo, not admin). Credentials go through a curl
config file so they never appear in a process list. The `artifactory-auth` and
`ca-bundle` workspaces are optional: runs with `upload=false` need neither.

**finally / purge-raw-on-failure** - if any task failed, deletes `raw/` so
un-sanitised data never lingers on the PVC.

**finally / retention** - runs after every run, success or failure, and never touches the
current run. It deletes earlier runs that never produced an archive (failed runs),
removes `clean/` and `raw/` from the rest, then keeps only the
newest `keepRuns` runs (default **3**) per clusterAlias - older run directories,
tarball and report included, are deleted. It reports PVC usage as the `pvcUsage`
result. runIds must sort chronologically; `scripts/start-run.sh` uses UTC timestamps.
With `upload=false` the PVC holds the only copy of a tarball, so fetch anything you
want to keep (`scripts/fetch-archive.sh`) or raise `keepRuns`.

Space per run after this: tarball (~100 MB on this cluster) + report. `package` already
deletes the current run's `clean/` once the tarball has been written and read back; a
run that fails the canary check keeps its `clean/` for inspection until the next run.

## Pod security

All task pods run as SA `must-gather-tasks`, which has no SCC grants, so OpenShift
admits them under **`restricted-v2`** (verified: `openshift.io/scc: restricted-v2` on
the pods). Every step also declares a restricted-compatible securityContext (non-root,
no privilege escalation, all capabilities dropped, RuntimeDefault seccomp) and
`HOME=/tmp`. OpenShift Pipelines' default `pipeline` SA would have received
`pipelines-scc`; that's why the run template sets `taskRunTemplate.serviceAccountName`.

## Using it

```bash
cp config/mgc-config.example.yaml config/mgc-config.yaml   # fill in
cp config/canaries.example.txt   config/canaries.txt       # fill in
ARTIFACTORY_USERNAME=... ARTIFACTORY_PASSWORD=... ./deploy.sh   # omit the vars for upload=false only
scripts/start-run.sh homelab true          # alias, upload -> prints the PipelineRun name
tkn pipelinerun logs -f -n must-gather-pipelines <name>
tkn pipelinerun describe -n must-gather-pipelines <name>   # results: archive, size, canaries...
scripts/fetch-archive.sh homelab <runId>   # copy the tarball here and verify sha256
```

### Choosing the type of must-gather

Parameter **`gatherType`** is a dropdown in the console Start dialog (Tekton enum):

| gatherType | Runs | Image comes from |
|---|---|---|
| `default` | standard cluster gather | `openshift/must-gather` image stream |
| `acm` | Advanced Cluster Management | ACM CSV's must-gather annotation, else `registry.redhat.io/rhacm2/acm-must-gather-rhel9:v<installed X.Y>` |
| `logging` | OpenShift Logging | CSV annotation, else the running `cluster-logging-operator` image (Red Hat's documented method) |
| `acs` | Advanced Cluster Security | CSV annotation only - ACS doesn't publish a must-gather image, so without one the run stops and points you to `roxctl central debug download-diagnostics` |
| `odf` | OpenShift Data Foundation | CSV annotation, else `registry.redhat.io/odf4/odf-must-gather-rhel9:v<installed X.Y>` |
| `oadp` | OADP (backup/restore) | CSV annotation |
| `gitops` | OpenShift GitOps | CSV annotation |
| `custom` | whatever is in `mustGatherImages` (space-separated) | you |

- The operator has to be installed; otherwise the gather task stops at once with
  "that operator is not installed on this cluster" and leaves nothing on the PVC.
- Using the image the installed operator's CSV advertises keeps the gather matched to
  the installed version; `registry.redhat.io` images need the cluster pull secret.
- **`includeDefault`** (default `true`) also runs the standard cluster gather in the same
  must-gather - usually what support asks for. Set `false` for the operator gather only.
- The type is part of the archive name: `<alias>-<runId>-<gatherType>-must-gather-sanitised.tar.gz`.
- An invalid value (e.g. from the CLI) fails the run with `InvalidParamValue` before any task starts.
- CLI: `scripts/start-run.sh <alias> <upload> <gatherType> <includeDefault>`, e.g.
  `scripts/start-run.sh homelab true oadp true`; for `custom` set `MUST_GATHER_IMAGES="img1 img2"`.
- Scheduled runs use `GATHER_TYPE` / `INCLUDE_DEFAULT` in `04-scheduler.yaml` (default: `default`).

### Scheduled runs

CronJob `must-gather-daily` starts a run every day at **02:00 Europe/London** as service
account **`must-gather-scheduler`**, so nothing depends on anyone's login. That SA can
only `create`/`get`/`list` PipelineRuns in `must-gather-pipelines` - it can't read
Secrets, create pods or touch other namespaces. The run itself then uses the same
identities as a manual one (`must-gather-tasks` for the pods, `must-gather-runner` for
the gather), with `upload=true` and `since=24h`.

- It builds the run from ConfigMap `mg-pipelinerun-template` (= `tekton/pipelinerun-template.yaml`),
  so scheduled and `start-run.sh` runs are identical. Re-create the ConfigMap after editing the template.
- Scheduled runs carry the label `must-gather/trigger=schedule`:
  `tkn pipelinerun list -n must-gather-pipelines --label must-gather/trigger=schedule`
- If a run is still in progress when the next slot comes, that slot is skipped (runs share one PVC).
- Change schedule, time zone or alias in `04-scheduler.yaml`; pause with
  `oc patch cronjob must-gather-daily -n must-gather-pipelines -p '{"spec":{"suspend":true}}'`.
- Run it now, as the SA: `oc create job --from=cronjob/must-gather-daily mg-now -n must-gather-pipelines`

### Starting from the OpenShift console

The console's **Start** dialog does not know this pipeline's bindings and defaults every
workspace to *Empty Directory* and the service account to `pipeline`. Set:

| Field | Value |
|---|---|
| Service account (under *Advanced*) | `must-gather-tasks` |
| `gatherType` | pick from the dropdown (see above) |
| `includeDefault` | `true` to also run the standard gather |
| `data` | PersistentVolumeClaim → `must-gather-data` |
| `kubeconfig` | Secret → `must-gather-kubeconfig` |
| `mgc-config` | Secret → `mgc-config` |
| `artifactory-auth` | Secret → `artifactory-auth` (**required** - `upload` defaults to `true`) |
| `ca-bundle` | leave empty |

Leaving `artifactory-auth` empty with the default `upload=true` fails the upload
task with a message saying so - set `upload` to `false` to keep the archive on the PVC only.
With an empty `kubeconfig` workspace the gather task stops immediately with
"no kubeconfig in the 'kubeconfig' workspace" (before this guard existed, `oc` fell back
to the pod's own `pipeline` SA and failed with *cannot create resource "namespaces"*).
`scripts/start-run.sh` sets all of this for you.

Changing what gets hidden: edit `config/mgc-config.yaml` / `config/canaries.txt`, then
```bash
oc create secret generic mgc-config -n must-gather-pipelines \
  --from-file=config.yaml=config/mgc-config.yaml --from-file=canaries.txt=config/canaries.txt \
  --dry-run=client -o yaml | oc apply -f -
```
Every value you obfuscate should also be a canary - that's what proves it worked.

## OKD

This pipeline was originally specified for a disconnected OCP cluster. For the connected
OKD 4.22 single-node home-lab cluster it was adapted as follows:

- **Tekton**: Red Hat OpenShift Pipelines 1.24 was already installed on this cluster
  (`tekton.dev/v1` served), so the community Tekton Operator was not needed.
- **Images**: no mirror registry. `cliImage` = `quay.io/openshift/origin-cli:4.22`
  (matches the cluster minor; checked it contains bash, tar and rsync). `mgcImage` is
  built in-cluster by a Docker-strategy BuildConfig into the internal registry
  (`image-registry.openshift-image-registry.svc:5000/must-gather-pipelines/must-gather-clean:latest`).
  The Containerfile downloads the must-gather-clean v0.0.5 linux release for the build
  host's arch (amd64 here; arm64 supported too) and verifies both the tarball and the
  binary against the release's published `SHA256_SUM`.
- **must-gather images**: `mustGatherImages` empty -> default OKD gather only.
- **Target**: gathers from the cluster it runs on via the kubeconfig-Secret approach
  (SA `must-gather-runner` + cluster-admin + token, API `https://kubernetes.default.svc`).
- **Storage**: 10Gi PVC on the default StorageClass `ceph-block` (Rook-Ceph, 247 GiB
  free at setup; Ceph reports HEALTH_WARN as usual for a single-node, 1-replica pool).
- **mgc-config**: example values replaced with the cluster's base domain, infra name,
  VPS/node name, public IP and admin username (kept out of git - see `config/`).
- **Pod security**: `restricted-v2`, no SCC changes (see above).
- **Artifactory**: the original OKD brief assumed there was none (`upload=false`,
  `artifactory-auth` optional). The cluster does run Artifactory, so uploads are enabled
  to the existing `generic-local` repository using the existing pipeline credential.
  `artifactory-auth` remains an optional workspace, so `scripts/start-run.sh homelab false`
  still works without it.
- **Fixed along the way**: must-gather-clean hangs in pipe mode without
  `< /dev/null`; tool output that contains un-sanitised names is kept out of step logs.
