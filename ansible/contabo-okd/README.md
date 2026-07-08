# ansible/contabo-okd

Repeatable day-2 configuration for the Contabo-hosted OKD single-node cluster
(`*.apps.okd.funky-bash.com`): pull secret, operator catalogs, all 17 real operator
Subscriptions, and every operand config (Vault, external-secrets, Grafana + monitoring
stack, Keycloak SSO + realm, Tekton pipelines) - everything under
`operators/subscription/*` in this repo.

This is the piece meant to answer "if I resize the VPS, how do I get back to this exact
state?" - see `terraform/contabo-okd/README.md` for the resize itself (which, done via
Contabo's live migration, keeps the running cluster - you mainly need this playbook for
a from-scratch rebuild, or to re-apply anything that was trimmed/skipped for resource
pressure once the resize gives you headroom).

## How it works

Every task talks to the cluster over SSH by running `oc` **on the node itself**, using
the node's local recovery kubeconfig
(`/etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs/localhost-recovery.kubeconfig`,
root-only - hence `become: true` throughout). There's no separate kubeconfig or oc
client needed on your control machine.

Every operator/operand manifest is applied straight from GitHub via kustomize's remote
support - e.g. `oc apply -k https://github.com/computab0y/devops//operators/subscription/grafana/overlay/env?ref=main`
- so the playbook always deploys whatever is currently committed to this repo. There's
no separate file-sync step.

Most `operators/subscription/<name>` kustomizations bundle the OLM Subscription
*and* that operator's operand config (CRs) together, using ArgoCD sync-wave annotations
to order things for GitOps. Since this playbook doesn't use ArgoCD, it reproduces the
same effect with an explicit two-pass apply per operator (see
`tasks/deploy_operator.yml`): apply once (creates the namespace/Subscription; any
operand CRs whose CRDs don't exist yet fail harmlessly), wait for the operator's CSV to
reach `Succeeded` (auto-approving the InstallPlan first for the several operators that
use `installPlanApproval: Manual`), then apply again (the operand CRs now resolve).

`sso` (Postgres + Keycloak + realm import) and `tekton` (pipelines) need a bit more than
the generic two-pass flow, so they get their own task files:

- `tasks/deploy_sso.yml` - also creates a static hostPath `PersistentVolume` for Postgres
  (this cluster has no StorageClass/CSI provisioner at all) with the SELinux relabel it
  needs, then - once the Keycloak instance and realm import are both ready - fetches the
  Keycloak-generated `openshift` client secret via the Admin REST API and the cluster's
  default ingress CA, and stores both as secrets in `openshift-config` so the OAuth
  OpenID identity provider (already applied, referencing those secret names) can
  actually authenticate. `oc login` still works with your existing HTPasswd user the
  whole time - this only adds the Keycloak IDP alongside it.
- `tasks/deploy_tekton.yml` - also flips the `enable-param-enum` feature flag on the
  cluster's `TektonConfig` (off by default), which `ftp-file-pipeline`'s `enum`-typed
  params need. **No PipelineRuns are triggered** - `ftp-file-pipeline` targets a private
  IP on Ray's local Mac/Parallels network by default, unreachable from this cluster; the
  Task/Pipeline definitions deploy fine and are ready to use once pointed at a real FTP
  host.

`tasks/deploy_vault.yml` is the simple case - Vault has no OLM Subscription, it's a
plain Deployment, so it's a single apply.

## Prerequisites

- SSH access to the node (see `inventory.ini` - defaults match the current instance;
  update `ansible_host` if the IP ever changes after a non-live-migration reinstall).
- A real Red Hat Customer Portal pull secret downloaded from
  https://console.redhat.com/openshift/install/pull-secret, saved locally at the path
  set in `vars.yml`'s `pull_secret_path` (default `~/Downloads/pull-secret.txt`).
  `registry.redhat.io` and `registry.connect.redhat.com` reject the placeholder pull
  secret `openshift-install` generates by default.
- Ansible >= 2.14 or so on your control machine. No extra collections needed - everything
  here uses `ansible.builtin.*` modules.

## Usage

```bash
cd ansible/contabo-okd
ansible-playbook playbook.yml --tags bootstrap   # pull secret, catalogs, node label
ansible-playbook playbook.yml --tags operators    # all 17 operator Subscriptions
ansible-playbook playbook.yml --tags operands     # vault, sso, tekton (see above)
ansible-playbook playbook.yml                     # everything, in order
```

Safe to re-run in full any time - every task is written to be idempotent (`oc apply`,
`until` loops that no-op once already-true, etc).

## Known limitations (carried over from the live deployment, not fixed by this playbook)

- **`edb-postgresql` (EDB Postgres for Kubernetes / cloud-native-postgresql) stays
  blocked.** Its manager image is pulled from `docker.enterprisedb.com` - a separate
  registry from `registry.redhat.io` - and needs its own
  `postgresql-operator-pull-secret` with EnterpriseDB credentials this deployment
  doesn't have. The playbook's wait-for-CSV step for this one is allowed to time out
  (`ignore_errors: true`) rather than failing the whole run; every other operator still
  gets deployed. See `operators/subscription/edb-postgresql/base/subscription.yaml` for
  what you'd need to unblock it.
- **Single node, no storage provisioner, finite headroom.** Everything above was
  deployed and verified stable on a Contabo Cloud VPS 30 (8 vCPU/24GB), but it sits
  around 70-90% CPU/memory with all of this running - there's very little room for
  anything more without either trimming something or upsizing (see
  `terraform/contabo-okd/README.md`).
