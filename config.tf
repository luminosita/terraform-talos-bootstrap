locals {
  indexes        = { for k in proxmox_virtual_environment_vm.this : k.name => { for index, name in k.network_interface_names : k.network_interface_names[index] => index } }
  ipv4_addresses = { for k in proxmox_virtual_environment_vm.this : k.name => { for iface_key, iface_value in local.indexes[k.name] : iface_key => k.ipv4_addresses[iface_value] } }
  vm_ips         = { for k, v in local.ipv4_addresses : k => v["eth0"][0] }
  ips            = { for k, v in var.talos_nodes : k => v.network.dhcp ? local.vm_ips[k] : v.network.ip }

  endpoints            = [for k, v in var.talos_nodes : local.ips[k] if v.machine_type == "controlplane"]
  worker_nodes         = [for k, v in var.talos_nodes : local.ips[k] if v.machine_type == "worker"]
  cluster_endpoint     = coalesce(var.talos_cluster_config.vip, local.endpoints[0])
  cluster_endpoint_url = "https://${local.cluster_endpoint}:${var.talos_cluster_config.endpoint_port}"
  extra_manifests = concat(var.talos_cluster_config.extra_manifests, [
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.talos_cluster_config.gateway_api_version}/standard-install.yaml",
    "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${var.talos_cluster_config.gateway_api_version}/config/crd/experimental/gateway.networking.k8s.io_tlsroutes.yaml"
  ])
}

resource "talos_machine_secrets" "this" {
  // Changing talos_version causes trouble as new certs are created
#  talos_version = local.talos_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.talos_cluster_config.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.talos_nodes : local.ips[k]]
  # Don't use vip in talosconfig endpoints
  # ref - https://www.talos.dev/v1.9/talos-guides/network/vip/#caveats
  endpoints = local.endpoints
}

resource "terraform_data" "cilium_bootstrap_inline_manifests" {
  input = [
    {
      name = "cilium-bootstrap"
      contents = templatefile("${path.module}/${var.talos_cluster_config.cilium.bootstrap_manifest_path}", {
        port    = var.talos_cluster_config.endpoint_port
        version = var.talos_cluster_config.cilium.version
      })
    },
    {
      name = "cilium-values"
      contents = yamlencode({
        apiVersion = "v1"
        kind       = "ConfigMap"
        metadata = {
          name      = "cilium-values"
          namespace = "kube-system"
        }
        data = {
          "values.yaml" = templatefile("${path.root}/${var.talos_cluster_config.cilium.values_file_path}", {
            cluster_name = var.talos_cluster_config.name
          })
        }
      })
    }
  ]
}

data "talos_machine_configuration" "this" {
  for_each     = var.talos_nodes
  cluster_name = var.talos_cluster_config.name
  # This is the Kubernetes API Server endpoint.
  # ref - https://www.talos.dev/v1.9/introduction/prodnotes/#decide-the-kubernetes-endpoint
  cluster_endpoint   = local.cluster_endpoint_url
  talos_version      = var.talos_cluster_config.talos_machine_config_version != null ? var.talos_cluster_config.talos_machine_config_version : (each.value.update == true ? var.talos_image.update_version : var.talos_image.version)
  kubernetes_version = var.talos_cluster_config.kubernetes_version
  machine_type       = each.value.machine_type
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  config_patches = [
    templatefile("${path.module}/machine-config/common.yaml.tftpl", {
      zone     = each.value.host_node
      group    = each.value.node_group
      region   = var.talos_cluster_config.region
      hostname = each.key
      network  = each.value.network
      vip      = var.talos_cluster_config.vip
    }), each.value.machine_type == "controlplane" ?
    templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
      # kubelet = var.talos_cluster_config.kubelet
      extra_manifests = jsonencode(local.extra_manifests)
      # api_server = var.talos_cluster_config.api_server
      inline_manifests = jsonencode(terraform_data.cilium_bootstrap_inline_manifests.output)
    }) : ""
  ]
}

resource "talos_machine_configuration_apply" "this" {
  depends_on                  = [proxmox_virtual_environment_vm.this]
  for_each                    = var.talos_nodes
  node                        = local.ips[each.key]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  lifecycle {
    #re-run config apply if vm changes
    replace_triggered_by = [proxmox_virtual_environment_vm.this[each.key]]
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]
  # Bootstrap with the first node. VIP not yet available at this stage, so cant use var.talos_cluster_config.endpoint as it may be set to VIP
  # ref - https://www.talos.dev/v1.9/talos-guides/network/vip/#caveats
  node                 = local.cluster_endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this
  ]
  skip_kubernetes_checks = false
  client_configuration   = data.talos_client_configuration.this.client_configuration
  control_plane_nodes    = local.endpoints
  worker_nodes           = local.worker_nodes
  endpoints              = local.endpoints
  timeouts = {
    read = "15m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]
  # If using VIP, it should be up by now, but to be safer retrive from one of the nodes
  # As mentioned don't use talosctl on vip
  # ref - https://www.talos.dev/v1.9/talos-guides/network/vip/#caveats
  # In kubeconfig endpoint will be polulated by cluster_endpoint from machine-config
  node                 = local.cluster_endpoint
  client_configuration = talos_machine_secrets.this.client_configuration
  timeouts = {
    read = "1m"
  }
}
