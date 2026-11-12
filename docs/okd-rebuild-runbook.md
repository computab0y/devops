# Rebuilding the Contabo OKD cluster from scratch

The single-node OKD cluster at `api.okd.funky-bash.com` (Contabo VPS 203424384) can be
rebuilt from this repo in three steps:

| Step | What | Where |
|---|---|---|
| 1 | Reinstall the VPS as Debian (**wipes the disk**, keeps the IP), point DNS at it | `terraform/contabo-okd-rebuild` |
| 2 | Install OKD 5 SNO by kexec into the SCOS live image, carve the Ceph partition, save credentials, create break-glass access | `ansible/contabo-okd-install` |
| 3 | Day-2: catalogs, operators, Rook-Ceph, registry, certificates, Lightspeed, Keycloak, Tekton, Nextcloud, CNPG, Artifactory, headscale, Argo CD apps | `ansible/contabo-okd` |

`scripts/rebuild-contabo-okd.sh` runs all three in order and asks you to type the instance
ID before wiping anything.

> **Configuration is rebuilt. Data is not.** A rebuild gives you empty databases, an empty
> Artifactory, new headscale keys and an empty registry. Take the backups in the next
> section **before** step 1.

## 1. Back up data first

| What | How | Restore |
|---|---|---|
| homelab-pg (CNPG) | `oc exec -n pgd-homelab <primary> -- pg_dumpall -U postgres \| gzip > homelab-pg-$(date +%Y%m%d).sql.gz` | `gunzip -c … \| oc exec -i -n pgd-homelab <primary> -- psql -U postgres` |
| PGD (beacon) | `pg_dumpall` from a PGD data pod, same as above | `psql` into the new group |
| Artifactory | Admin → Export System, or copy the `artifactory-volume-artifactory-0` PVC | Import System |
| headscale | copy `db.sqlite` and `noise_private.key` out of the `headscale-data` PVC | copy them into the new PVC before the first start, so clients don't need to re-register |
| Keycloak realm/users | Realm settings → Partial export (or `kc.sh export`) | import into the `openshift` realm |
| Nextcloud | copy `nextcloud-data-pvc` | copy back |
| etcd | `cluster-backup.sh` (see the 2026-11 upgrade notes). Only useful for restoring the *same* cluster, not a rebuild | - |

Vault runs in dev mode, so nothing persists. Re-seed it from your sources of truth.

## 2. Inputs to have on the Mac (none of these go in git: the repo is public)

| File / value | Used by | Notes |
|---|---|---|
| `terraform/contabo-okd-rebuild/terraform.tfvars` | step 1 | Contabo API creds, Cloudflare token + zone, `product_id`, `debian_image_id` (look both up with `cntb`) |
| `~/Downloads/pull-secret.txt` | steps 2–3 | console.redhat.com pull secret (registry.redhat.io operator catalogs) |
| `~/.ssh/contabo_okd_ssh_key` | steps 1–3 | created if missing |
| `ansible/contabo-okd/vars.local.yml` | step 3 | at least `acme_email: you@…`; pass with `-e @vars.local.yml` |
| `~/.okd-breakglass/cloudflare-api-token` | step 3, certs | Zone:DNS:Edit token for the Let's Encrypt DNS-01 wildcard |
| `~/.okd-breakglass/anthropic-api-key` | step 3, Lightspeed | create it in a normal terminal: `read -rs KEY; printf %s "$KEY" > ~/.okd-breakglass/anthropic-api-key; unset KEY; chmod 600 ~/.okd-breakglass/anthropic-api-key`. The account needs credits |
| `~/okd-install-contabo/secrets/artifactory-oidc-client-secret` | step 3, Artifactory login proxy | secret of the `artifactory` client in Keycloak realm `openshift` (create the client after sso runs, then re-run `--tags operand-artifactory`) |
| EDB subscription token | `apps/pgd` (manual) | only if you want beacon's PGD database |

Tools: `terraform`, `ansible-playbook` (ansible-core ≥ 2.16), `oc`, `helm`, `htpasswd`.

## 3. Run it

```bash
cd ~/devops
scripts/rebuild-contabo-okd.sh                         # all three steps
# or step by step:
SKIP_TERRAFORM=1 scripts/rebuild-contabo-okd.sh        # VPS already Debian
cd ansible/contabo-okd && ansible-playbook playbook.yml -e @vars.local.yml --tags storage
```

Useful day-2 tags: `bootstrap`, `cluster`, `storage`, `registry`, `operators`, `certs`,
`lightspeed`, `operands`, `operand-sso`, `operand-cnpg`, `operand-artifactory`,
`operand-headscale`, `operand-argocd`.

Afterwards:
- Copy `~/okd-install-contabo/auth/kubeconfig-breakglass` to `~/.okd-breakglass/`.
- Back up `~/okd-install-contabo/auth/`, `~/okd-install-contabo/secrets/` and the SSH key
  somewhere off the Mac.
- Restore the data from section 1.
- Optional: EDB PGD for beacon, see `apps/pgd/README.md`.

## Before any reboot or upgrade on this node

This is a single node, and its storage (Ceph RBD/CephFS) is served from the same node.
On 2026-11-10 the OKD 5.0 reboot hung for 30 minutes on volume mounts served from inside
the cluster (NFS then, Ceph has the same risk). systemd force-rebooted, skipped
`ostree-finalize-staged`, and the staged OS update was lost.

Before an upgrade or a MachineConfig change that reboots the node, stop everything that
mounts cluster-served storage, and check that nothing is still mounted:

```bash
oc scale deploy -n cnpg-system cnpg-controller-manager --replicas=0
oc annotate clusters.postgresql.cnpg.io -n pgd-homelab homelab-pg cnpg.io/hibernation=on --overwrite
oc scale sts -n artifactory --all --replicas=0
oc scale deploy -n pgd-homelab --all --replicas=0
oc scale deploy -n headscale --all --replicas=0
oc patch configs.imageregistry.operator.openshift.io cluster --type merge -p '{"spec":{"managementState":"Unmanaged"}}'
oc scale deploy -n openshift-image-registry image-registry --replicas=0
# (EDB PGD: scale pgd-operator to 0, annotate each group k8s.enterprisedb.io/hibernation=on)
oc debug node/<node> -- chroot /host sh -c 'mount | grep -E "rbd|ceph|nfs" | wc -l'   # want 0
```

Reverse it once the node is back. If the MCD is stuck with "unexpected on-disk state"
after a lost staged deployment, run `touch /run/machine-config-daemon-force` on the node
(with consumers stopped) and it re-stages and reboots.

Also on this node:
- Don't set the console operator to Unmanaged. It marks ClusterVersion Failing, which
  blocks upgrades.
- The node is **CPU-request bound** (~83% reserved, ~38% used). New workloads go Pending
  with "Insufficient cpu" long before the CPU is busy. Set small requests.

## What the live cluster looked like when this was written (2026-11-11)

| Component | Version / setting |
|---|---|
| OKD | 5.0.0-okd-scos.5, channel `stable-scos-5`, SCOS 10.0.20261014-0, CRI-O 1.36.4 |
| Disk | sda4 root 249.5G, sda5 `rookdata0` 250G (Ceph OSD) |
| Rook / Ceph | Rook v1.20.7, Ceph v19.2.6, 1 mon/mgr/OSD, pools size 1 (HEALTH_WARN expected) |
| StorageClasses | `ceph-block` (default), `ceph-filesystem`, `ceph-bucket` |
| Image registry | Managed, PVC `image-registry-storage-ceph` (CephFS RWX, 100Gi) |
| CloudNativePG | 1.25.0, cluster `homelab-pg` (3 × PostgreSQL 17.2, ceph-block 20Gi) |
| EDB | pg4k `docker.enterprisedb.com/k8s/edb-postgres-for-cloudnativepg@sha256:62ae236c…`, PGD `…/edb-postgres-for-cloudnativepg-global-cluster@sha256:b57f6a8e…`, image `postgresql-pgd:18.4-pgd640-expanded-ubi9` |
| Artifactory | chart `jfrog/artifactory-jcr` 107.146.29 (app 7.146.29), CPU requests 50m/container |
| Lightspeed | operator 1.1.3, provider `openai`-type → `api.anthropic.com/v1`, model `claude-opus-4-6` |
| headscale | 0.29.3, headscale-admin 0.24 |
| OLM operators | cert-manager (stable-v1), gitops (latest), external-secrets (alpha, community), keycloak (fast, community), oadp (stable-1.4), amq-streams, devworkspace, servicemesh 2.6, kiali, pipelines (latest), lightspeed (stable) |
| Not working on live | loki, cluster-logging, elasticsearch subscriptions: ResolutionFailed since OKD 5 (moved to `optional_operators`) |

Not carried into the rebuild: the in-cluster NFS server and `nfs-client` provisioner, and
`local-path` (nothing uses them any more), plus the test namespaces (`rgb-test`, `s3-demo`,
`mg-disconnected-test`, …).

## Known gaps / untested

- The destructive path (Terraform reinstall → kexec → bootstrap-in-place) has been
  validated (`terraform validate`, `ansible-playbook --syntax-check`, template rendering)
  but has **not** been run against Contabo. If the VPS doesn't come back after kexec,
  check the VNC console.
- The `rookdata0` partition MachineConfig is applied by ignition on first boot. Check it
  with `lsblk` before day-2. The Rook task stops if the partition is missing.
- The Keycloak OIDC client for Artifactory and the EDB operators are manual (see above).
- Lightspeed: switch to `claude-opus-5-5` once lightspeed-operator ships the native
  `anthropic` provider or stops sending `temperature`.
