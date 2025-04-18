resource "talos_machine_secrets" "this" {
  talos_version = var.cluster.talos_machine_config_version
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  nodes                = [for k, v in var.nodes : v.network.ip]
  # Don't use vip in talosconfig endpoints
  # ref - https://www.talos.dev/v1.9/talos-guides/network/vip/#caveats
  endpoints = [for k, v in var.nodes : v.network.ip if v.machine_type == "controlplane"]
}

resource "terraform_data" "cilium_bootstrap_inline_manifests" {
  input = [
    {
      name = "cilium-bootstrap"
      contents = templatefile("${path.module}/${var.cluster.cilium.bootstrap_manifest_path}", {
        port    = var.cluster.endpoint_port
        version = var.cluster.cilium.version
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
          "values.yaml" = templatefile("${path.root}/${var.cluster.cilium.values_file_path}", {
            cluster_name = var.cluster.name
          })
        }
      })
    }
  ]
}

data "talos_machine_configuration" "this" {
  for_each     = var.nodes
  cluster_name = var.cluster.name
  # This is the Kubernetes API Server endpoint.
  # ref - https://www.talos.dev/v1.9/introduction/prodnotes/#decide-the-kubernetes-endpoint
  cluster_endpoint = "https://${var.cluster.endpoint}:${var.cluster.endpoint_port}"
  # @formatter:off
  talos_version      = var.cluster.talos_machine_config_version #!= null ? var.cluster.talos_machine_config_version : (each.value.update == true ? var.image.update_version : var.image.version)
  kubernetes_version = var.cluster.kubernetes_version
  # @formatter:on
  machine_type    = each.value.machine_type
  machine_secrets = talos_machine_secrets.this.machine_secrets
  config_patches = [
    templatefile("${path.module}/machine-config/common.yaml.tftpl", {
      node_name    = each.value.host_node
      cluster_name = var.cluster.region
      hostname     = each.key
      network      = each.value.network
      # dhcp         = each.value.network.dhcp
      # ip           = each.value.network.ip
      # mac_address = lower(each.value.network.mac_address)
      # gateway      = each.value.network.gateway
      # subnet_mask  = each.value.network.subnet_mask
      vip = var.cluster.vip
    }), each.value.machine_type == "controlplane" ?
    templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
      # kubelet = var.cluster.kubelet
      extra_manifests = jsonencode(var.cluster.extra_manifests)
      # api_server = var.cluster.api_server
      inline_manifests = jsonencode(terraform_data.cilium_bootstrap_inline_manifests.output)
    }) : ""
  ]
}

resource "talos_machine_configuration_apply" "this" {
  #  depends_on = [proxmox_virtual_environment_vm.this]
  for_each                    = var.nodes
  node                        = each.value.network.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
  # lifecycle {
  # re-run config apply if vm changes
  #   replace_triggered_by = [proxmox_virtual_environment_vm.this[each.key]]
  # }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]
  # Bootstrap with the first node. VIP not yet available at this stage, so cant use var.cluster.endpoint as it may be set to VIP
  # ref - https://www.talos.dev/v1.9/talos-guides/network/vip/#caveats
  node                 = [for k, v in var.nodes : v.network.ip if v.machine_type == "controlplane"][0]
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this
  ]
  skip_kubernetes_checks = false
  client_configuration   = data.talos_client_configuration.this.client_configuration
  control_plane_nodes    = [for k, v in var.nodes : v.network.ip if v.machine_type == "controlplane"]
  worker_nodes           = [for k, v in var.nodes : v.network.ip if v.machine_type == "worker"]
  endpoints              = data.talos_client_configuration.this.endpoints
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
  node                 = [for k, v in var.nodes : v.network.ip if v.machine_type == "controlplane"][0]
  client_configuration = talos_machine_secrets.this.client_configuration
  timeouts = {
    read = "1m"
  }
}
