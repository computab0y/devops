# apps/pgd: EDB Postgres Distributed (optional, manual)

Database for **beacon** (`apps/argocd/beacon-root.yaml`). This step isn't automated, because
EDB's operators and images come from `docker.enterprisedb.com`, which needs an **EDB
subscription token**. That token can't be committed (this repo is public) and isn't
generated anywhere.

Live cluster (2026-11):
- EDB Postgres for Kubernetes (`postgresql-operator-controller-manager`, in `openshift-operators`)
- EDB PGD operator (`pgd-operator-controller-manager`, in `pgd-operator-system`)
- PGDGroup `homelab-pgd` in `pgd-group-homelab` (2 data nodes plus a witness, on ceph-block)

## Rebuild steps

Run these after the day-2 playbook. You need cert-manager and Rook-Ceph in place first.

1. Install both EDB operators by following EDB's install docs for your token. Use the
   same versions as before if possible; their image digests are in
   `docs/okd-rebuild-runbook.md`.
2. Create the image pull secret in each namespace that pulls EDB images:
   ```bash
   oc create secret docker-registry pgd-operator-pull-secret -n pgd-group-homelab \
     --docker-server=docker.enterprisedb.com --docker-username=k8s --docker-password="$EDB_TOKEN"
   ```
3. Create beacon's role password (the PGD operator manages the role):
   ```bash
   oc create secret generic beacon-db-password -n pgd-group-homelab --type=kubernetes.io/basic-auth \
     --from-literal=username=beacon --from-literal=password="$(openssl rand -base64 24)"
   ```
4. `oc apply -k apps/pgd`

The PGDGroup's CA chain is `ClusterIssuer homelab-pgd-selfsigned-issuer` (in
`platform/cert-manager`) → `Certificate homelab-pgd-ca-cert` → `Issuer homelab-pgd-ca-issuer`.
