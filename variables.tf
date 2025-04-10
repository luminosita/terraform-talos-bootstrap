variable "cluster" {
  description = "Cluster configuration"
  type = object({
    name          = string
    endpoint      = string
    endpoint_port = optional(string, "6443")
    vip           = optional(string)
    network = object({
      gateway     = string
      subnet_mask = optional(string, "24")
    })
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
    host_node     = string
    machine_type  = string
    datastore_id  = string
    ip            = string
    dns           = optional(list(string))
    mac_address   = string
    vm_id         = number
    cpu           = number
    ram_dedicated = number
    update        = optional(bool, false)
    igpu          = optional(bool, false)
  }))
}
