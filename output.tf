output "machine_config" {
  value = data.talos_machine_configuration.this
}

output "client_configuration" {
  value     = data.talos_client_configuration.this
  sensitive = true
}

output "kube_config" {
  value =  talos_cluster_kubeconfig.this
  sensitive = true
}

output "cluster_endpoint" {
  value = local.cluster_endpoint
}

output "ipv4_addresses" {
  value = local.vm_ips
}
