# terraform/contabo-okd

> **Full rebuild from scratch** (wipe + reinstall OKD): see `terraform/contabo-okd-rebuild`,
> `ansible/contabo-okd-install/README.md` and `scripts/rebuild-contabo-okd.sh`. This module
> only manages the running instance and never reinstalls it.

Infrastructure-as-code for the Contabo-hosted OKD single-node cluster at
`*.apps.okd.funky-bash.com`. This manages two things:

1. The Contabo compute instance itself (size/plan, display name).
2. The Cloudflare DNS records that point at it (`api.okd.funky-bash.com` and
   `*.apps.okd.funky-bash.com`).

It deliberately does **not** attempt to script the OKD bootstrap (FCOS image build,
ignition, `openshift-install`) - that was a one-time, largely manual process. See
`ansible/contabo-okd/` for the repeatable **day-2 configuration** (pull secret, operator
catalogs/subscriptions, and every operand in `operators/subscription/*`), which is what
you'd re-run after a resize.

## First-time setup: import the existing instance and DNS records

The instance and DNS records already exist (created manually). Run these once so
Terraform adopts them instead of trying to create duplicates or conflicting resources:

```bash
cd terraform/contabo-okd
cp terraform.tfvars.example terraform.tfvars   # fill in real values, never commit this file
terraform init

terraform import contabo_instance.okd_node 203424384
terraform import cloudflare_dns_record.api '<zone_id>/<api_record_id>'
terraform import cloudflare_dns_record.apps_wildcard '<zone_id>/<apps_wildcard_record_id>'
```

Get the DNS record IDs with `cloudflare_zone_id` set:

```bash
curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/<zone_id>/dns_records" | jq '.result[] | {id, name, type}'
```

Then `terraform plan` - it should show **no changes** if the imports and tfvars match
reality. If it wants to change `display_name` or similar cosmetic fields, that's fine to
apply; if it wants to change `image_id`, `root_password`, `ssh_keys`, or `user_data`,
**stop** - applying those would trigger a forced reinstall and wipe the running cluster.

## Resizing the VPS (the reason this exists)

Contabo's API/Terraform provider does **not** support resizing an instance in place by
changing `product_id`. Resizing is a manual action in the Customer Control Panel with two
methods:

- **New deployment** - free, but wipes the disk and assigns a new IP. Do not use this on
  a live cluster.
- **Live migration** - keeps data, disk, and IP; has a one-time service fee shown at
  upgrade time. This is the one to use.

Workflow:

1. In the Contabo Customer Control Panel, find the instance, click **More -> Upgrade**,
   choose the target plan, and select **Live Migration**.
2. Wait for the migration to complete (server stays online).
3. Update `product_id` (and `instance_ipv4` only if it somehow changed) in your
   `terraform.tfvars` to match the new plan.
4. Run `terraform plan` - it should show only the `product_id` (and read-only spec)
   attributes changing to reflect the new size, no destructive actions. `terraform
   apply` to reconcile state.
5. Re-run the Ansible playbook in `ansible/contabo-okd/` (or just the `operands` tag) if
   you want to redeploy anything that was trimmed/skipped for resource pressure before
   the resize - the whole point of the resize is to give those operands headroom.

## Variables

See `variables.tf` for full descriptions. Sensitive values (Contabo API credentials,
Cloudflare API token) should only ever live in your local `terraform.tfvars` (gitignored)
or a secrets-managed CI variable - never commit them.
