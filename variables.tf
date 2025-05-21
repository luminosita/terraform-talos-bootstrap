variable "talos_image" {
  description = "Talos image configuration"
  type = object({
    factory_url = optional(string, "https://factory.talos.dev")

    schematic        = optional(string, "schematic.yaml")
    version          = string
    update_schematic = optional(string, "schematic.yaml")
    update_version   = optional(string)

    arch                  = optional(string, "amd64")
    platform              = optional(string, "nocloud")
    image_filename_prefix = string

    datastore_id = string
  })
}

variable "talos_cluster_config" {
  description = "Cluster configuration"
  type = object({
    name                         = string
    endpoint_port                = optional(string, "6443")
    vip                          = optional(string)
    talos_machine_config_version = optional(string)
    kubernetes_version           = string
    region                       = string
    gateway_api_version          = string
    extra_manifests              = optional(list(string), [])
    kubelet                      = optional(string)
    api_server                   = optional(string)
    cilium = object({
      version                   = string
      extra_bootstrap_manifests = optional(list(string))
      values_file_path          = string
    })
  })
}

variable "talos_nodes" {
  description = "Configuration for cluster nodes"
  type = map(object({
    host_node    = string
    node_group   = optional(string)
    machine_type = string
    datastore_id = string
    network = object({
      dhcp        = bool
      ip          = optional(string)
      dns         = optional(list(string))
      mac_address = string
      gateway     = optional(string)
      subnet_mask = optional(string, "24")
      device      = optional(string, "vmbr0")
      vlan_id     = optional(number)
    })
    vm_id         = number
    cpu           = number
    ram_dedicated = number
    update        = optional(bool, false)
    igpu          = optional(bool, false)
  }))
  validation {
    // @formatter:off
    condition     = length([for n in var.talos_nodes : n if contains(["controlplane", "worker"], n.machine_type)]) == length(var.talos_nodes)
    error_message = "Node machine_type must be either 'controlplane' or 'worker'."
    // @formatter:on
  }
}
