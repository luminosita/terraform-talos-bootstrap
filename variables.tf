variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name                         = string
    endpoint                     = string
    endpoint_port                = optional(string, "6443")
    vip                          = optional(string)
    talos_machine_config_version = string
    kubernetes_version           = string
    region                       = string
    extra_manifests              = optional(list(string))
    kubelet                      = optional(string)
    api_server                   = optional(string)
    cilium = object({
      version = string

      bootstrap_manifest_path = optional(string, "./inline-manifests/cilium-install.tftpl")
      values_file_path        = string
    })
  })
}

variable "nodes" {
  description = "Configuration for cluster nodes"
  type = map(object({
    host_node    = string
    machine_type = string
    datastore_id = string
    network = object({
      dhcp        = bool
      ip          = optional(string)
      dns         = optional(list(string))
      mac_address = string
      gateway     = optional(string)
      subnet_mask = optional(string, "24")

      pod_cidr     = optional(string)
      service_cidr = optional(string)
    })
    vm_id         = number
    cpu           = number
    ram_dedicated = number
    update        = optional(bool, false)
    igpu          = optional(bool, false)
  }))
  validation {
    // @formatter:off
    condition     = length([for n in var.nodes : n if contains(["controlplane", "worker"], n.machine_type)]) == length(var.nodes)
    error_message = "Node machine_type must be either 'controlplane' or 'worker'."
    // @formatter:on
  }
}
