output "instance_id" {
  value = contabo_instance.okd_node.id
}

output "instance_status" {
  value = contabo_instance.okd_node.status
}

output "api_url" {
  value = "https://api.${var.cluster_name}.${var.base_domain}:6443"
}

output "next_step" {
  value = "cd ../../ansible/contabo-okd-install && ansible-playbook playbook.yml"
}
