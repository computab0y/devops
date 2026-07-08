# Contabo compute instance running the OKD single-node cluster.
#
# This uses `existing_instance_id` to bring the ALREADY-RUNNING instance under Terraform
# management (import it first - see README) rather than declaring a brand new instance,
# since re-creating it would wipe the running OKD cluster.
#
# CAUTION: several attributes on this resource trigger a forced OS reinstall on change
# (image_id, root_password, ssh_keys, user_data - see provider docs). This config
# intentionally does NOT set any of those, so routine `terraform apply` runs are safe.
# display_name and product_id are the only two fields we manage here.
resource "contabo_instance" "okd_node" {
  existing_instance_id = var.existing_instance_id
  display_name         = var.display_name
  product_id           = var.product_id
  region               = var.region
}

# DNS - Cloudflare zone for the base domain. Both records already exist from the manual
# setup; import them (see README) before the first `terraform apply` so Terraform adopts
# them instead of trying to create duplicates.
resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = "api.${var.cluster_name}.${var.base_domain}"
  type    = "A"
  content = var.instance_ipv4
  ttl     = 300
  # Must stay un-proxied (grey-cloud): the OpenShift API and *.apps ingress need direct
  # TCP, not Cloudflare's HTTP(S) proxy.
  proxied = false
  comment = "OKD API - managed by terraform/contabo-okd"
}

resource "cloudflare_dns_record" "apps_wildcard" {
  zone_id = var.cloudflare_zone_id
  name    = "*.apps.${var.cluster_name}.${var.base_domain}"
  type    = "A"
  content = var.instance_ipv4
  ttl     = 300
  proxied = false
  comment = "OKD apps wildcard - managed by terraform/contabo-okd"
}
