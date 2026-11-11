# ansible/contabo-okd-install

**From-scratch** OKD single-node (SNO) install onto the Contabo VPS. This is the piece
that turns an empty VPS into a running cluster; `ansible/contabo-okd` (day-2) then
puts all the operators, Vault, Keycloak and Tekton back on top.

> Rebuilding wipes the VPS: Keycloak users/clients beyond the repo's realm files,
> Vault contents, Grafana/Loki data and every PV are lost. Only do it when the cluster
> is unrecoverable, or restore from OADP backups afterwards.

## The whole rebuild, in order

```bash
cd terraform/contabo-okd-rebuild
cp terraform.tfvars.example terraform.tfvars   # fill in; gitignored
cd ../..
scripts/rebuild-contabo-okd.sh                 # asks you to type the instance ID
```

That runs:

| Step | What | Where |
|---|---|---|
| 1 | Reinstall instance as Debian with your SSH key (keeps the IP), point DNS at it, write `inventory.ini` | `terraform/contabo-okd-rebuild` |
| 2 | Install OKD SNO, save credentials, create break-glass admin | this playbook |
| 3 | Day-2: catalogs, 17 operators, Vault, Keycloak + OAuth, Tekton | `ansible/contabo-okd` |

`SKIP_TERRAFORM=1 scripts/rebuild-contabo-okd.sh` skips step 1 if the VPS is already
a fresh Debian you can reach as root with the key.

## How the install works (no ISO upload, no rescue mode)

1. **facts** - reads IP, prefix, gateway, MAC, DNS and the root disk from the Debian
   host, so nothing network-related is hard-coded.
2. **prepare** (on your Mac, in `install_dir`, default `~/okd-install-contabo`):
   downloads `openshift-install` for `okd_version` from the okd-project GitHub release
   and verifies it against the release's `sha256sum.txt`; renders `install-config.yaml`
   (SNO, `platform: none`, bootstrap-in-place to the detected disk); adds a
   MachineConfig with a static NetworkManager keyfile (Contabo has no DHCP); builds
   `bootstrap-in-place-for-live-iso.ign`; reads the matching SCOS PXE artifact URLs and
   checksums from `openshift-install coreos print-stream-json`.
3. **install** (on the Debian host): downloads the SCOS kernel/initramfs/rootfs
   (checksum-verified), embeds the ignition and network keyfile with
   `coreos-installer pxe customize`, appends the rootfs so the live system runs
   entirely from RAM, and **kexecs** into it. The live system installs OKD to the disk
   it was just running Debian from and reboots into the installed node.
4. **wait** - `openshift-install wait-for bootstrap-complete` then `install-complete`.
5. **access**:
   - copies `auth/` (certificate-based admin kubeconfig + kubeadmin password) to
     `install_dir/auth/`
   - creates `openshift-config/htpass-secret` with user `breakglass` and a generated
     password (`install_dir/auth/breakglass-password`), wires it to the `developer`
     HTPasswd provider that `operators/subscription/sso/base/openshift-oauth.yaml`
     already declares, and gives it cluster-admin. Day-2 replaces the OAuth config but
     keeps that provider, so this login survives Keycloak outages.

## Keep these off the Mac as well (password manager / encrypted backup)

- `~/.ssh/contabo_okd_ssh_key` (+ `.pub`) - SSH to `core@<node>`; also used by day-2
- `~/okd-install-contabo/auth/` - `kubeconfig`, `kubeadmin-password`, `breakglass-password`

Losing all three - Keycloak down, no kubeadmin password, no node SSH key - is exactly
the lock-out this was written after (2026-09-27).

## Running parts of it

```bash
ansible-playbook playbook.yml --tags facts      # just show detected network/disk
ansible-playbook playbook.yml --tags prepare    # build ignition only, touch nothing remote
ansible-playbook playbook.yml --tags wait       # re-attach to an install in progress
ansible-playbook playbook.yml --tags access     # redo credentials backup / break-glass
```

## Not yet exercised end to end

Written and checked (Terraform `validate`, Ansible `--syntax-check`, template rendering
against real values) but the destructive path has not been run against Contabo yet.
Most likely rough edges on a first real run:
- kexec on Contabo's KVM - if the VPS doesn't come back as the SCOS live system, use the
  VNC console to see where it stopped
- `debian_image_id` / `product_id` must be looked up with `cntb` (see tfvars example)
