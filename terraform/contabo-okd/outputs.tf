output "instance_id" {
  value = contabo_instance.okd_node.id
}

output "instance_status" {
  value = contabo_instance.okd_node.status
}

output "instance_cpu_cores" {
  value = contabo_instance.okd_node.cpu_cores
}

output "instance_ram_mb" {
  value = contabo_instance.okd_node.ram_mb
}

output "api_url" {
  value = "https://api.${var.cluster_name}.${var.base_domain}:6443"
}

output "console_url" {
  value = "https://console-openshift-console.apps.${var.cluster_name}.${var.base_domain}"
}
