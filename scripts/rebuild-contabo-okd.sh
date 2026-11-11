#!/usr/bin/env bash
# Rebuild the Contabo OKD single-node cluster FROM SCRATCH.
#
#   1. terraform/contabo-okd-rebuild  - reinstall the VPS as Debian (WIPES THE DISK)
#   2. ansible/contabo-okd-install    - install OKD SNO onto it, save credentials,
#                                       create the break-glass admin
#   3. ansible/contabo-okd            - day-2: catalogs, operators, Vault, Keycloak, Tekton
#
# Usage: scripts/rebuild-contabo-okd.sh            (asks you to type the instance ID)
#        SKIP_TERRAFORM=1 scripts/rebuild-contabo-okd.sh   (VPS already reinstalled as Debian)
set -euo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
tf="$repo/terraform/contabo-okd-rebuild"

for bin in terraform ansible-playbook htpasswd oc; do
  command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }
done

tfvar() { sed -n "s/^$1 *= *\"\(.*\)\"/\1/p" "$tf/terraform.tfvars" 2>/dev/null; }
key="$(tfvar ssh_private_key_path)"; key="${key:-~/.ssh/contabo_okd_ssh_key}"; key="${key/#\~/$HOME}"
# Terraform uploads the .pub to Contabo, so the key has to exist before step 1.
[ -f "$key" ] || ssh-keygen -t ed25519 -N "" -C "okd-contabo" -f "$key"

if [ -z "${SKIP_TERRAFORM:-}" ]; then
  [ -f "$tf/terraform.tfvars" ] || { echo "create $tf/terraform.tfvars from terraform.tfvars.example first" >&2; exit 1; }
  id="$(tfvar existing_instance_id)"
  echo "This REINSTALLS Contabo instance $id and DESTROYS the cluster on it (Keycloak, Vault, all data)."
  read -r -p "Type the instance ID to continue: " typed
  [ "$typed" = "$id" ] || { echo "aborted"; exit 1; }
  terraform -chdir="$tf" init -input=false
  terraform -chdir="$tf" apply -var "confirm_wipe_instance_id=$typed"
  echo "waiting for Debian SSH on the reinstalled VPS..."
  until ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
        -i "$key" root@"$(tfvar instance_ipv4)" true 2>/dev/null; do sleep 15; done
fi

(cd "$repo/ansible/contabo-okd-install" && ansible-playbook playbook.yml)
(cd "$repo/ansible/contabo-okd" && ansible-playbook playbook.yml)
