variable "contabo_client_id" {
  type      = string
  sensitive = true
}

variable "contabo_client_secret" {
  type      = string
  sensitive = true
}

variable "contabo_api_user" {
  type      = string
  sensitive = true
}

variable "contabo_api_password" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token scoped to Zone:DNS:Edit on the base domain's zone."
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type = string
}

variable "existing_instance_id" {
  type        = string
  description = "Contabo instance to REINSTALL (203424384 at time of writing)."
}

variable "confirm_wipe_instance_id" {
  type        = string
  description = "Safety catch: must equal existing_instance_id or the plan fails. Leave unset in tfvars; pass it on the command line only when you really mean to wipe."
  default     = ""
}

variable "product_id" {
  type        = string
  description = "Current Contabo product ID of the instance (`cntb get instance <id> -o json`). Must match reality - this module does not resize."
}

variable "debian_image_id" {
  type        = string
  description = "Contabo standard image ID for Debian 12 (`cntb get images --standardImage=true | grep -i debian`)."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Private key used for root@Debian and core@SCOS. The matching .pub must exist next to it."
  default     = "~/.ssh/contabo_okd_ssh_key"
}

variable "instance_ipv4" {
  type        = string
  description = "Public IPv4 of the instance (unchanged by a reinstall)."
}

variable "display_name" {
  type    = string
  default = "okd-funky-bash"
}

variable "region" {
  type    = string
  default = "EU"
}

variable "base_domain" {
  type    = string
  default = "funky-bash.com"
}

variable "cluster_name" {
  type    = string
  default = "okd"
}
