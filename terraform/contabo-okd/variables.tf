variable "contabo_client_id" {
  type        = string
  description = "Contabo API OAuth2 client ID (Customer Panel -> API)."
  sensitive   = true
}

variable "contabo_client_secret" {
  type        = string
  description = "Contabo API OAuth2 client secret."
  sensitive   = true
}

variable "contabo_api_user" {
  type        = string
  description = "Contabo API username (your Contabo account email)."
  sensitive   = true
}

variable "contabo_api_password" {
  type        = string
  description = "Contabo API password."
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token scoped to Zone:DNS:Edit on the domain's zone."
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for the base domain (funky-bash.com)."
}

variable "existing_instance_id" {
  type        = string
  description = <<-EOT
    The Contabo compute instance ID that already runs the OKD single-node cluster
    (instance 203424384 at time of writing). Setting this makes Terraform manage the
    EXISTING instance in place instead of trying to create a new one.
  EOT
}

variable "product_id" {
  type        = string
  description = <<-EOT
    Contabo product/plan ID for the instance (e.g. the ID behind "Cloud VPS 30" vs
    "Cloud VPS 40"). Contabo product IDs aren't stable/guessable across accounts and
    regions - look up the exact ID two ways before setting this:
      1. `cntb get instances -o json` (https://github.com/contabo/cntb) shows the
         CURRENT product_id of instance var.existing_instance_id.
      2. https://contabo.com/en/product-list/?show_ids=true lists IDs for every
         plan, including the one you want to upgrade to.

    IMPORTANT: changing this value here does NOT resize the running instance. Contabo's
    API/provider does not support in-place resize - see the README in this directory
    for the required manual "Upgrade Now" -> "Live Migration" step in the Customer
    Control Panel. Update this variable to match AFTER completing that upgrade, so
    Terraform's recorded state matches reality; do not rely on `terraform apply` alone
    to perform the resize.
  EOT
}

variable "display_name" {
  type        = string
  description = "Display name shown for the instance in the Contabo Customer Panel."
  default     = "okd-funky-bash"
}

variable "region" {
  type        = string
  description = "Contabo region for the instance."
  default     = "EU"
}

variable "base_domain" {
  type        = string
  description = "Base domain the cluster is published under."
  default     = "funky-bash.com"
}

variable "cluster_name" {
  type        = string
  description = "OpenShift/OKD cluster name (used to build api.<cluster>.<base_domain> and *.apps.<cluster>.<base_domain>)."
  default     = "okd"
}

variable "instance_ipv4" {
  type        = string
  description = "Current public IPv4 of the instance, used for the DNS A records. Update after any reinstall that changes the IP (live-migration keeps the IP; a fresh reinstall does not)."
}
