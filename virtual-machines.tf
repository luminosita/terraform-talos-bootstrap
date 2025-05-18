locals {
  file_name = "${var.talos_image.image_filename_prefix}-${split("_",local.image_id)[0]}-${split("_", local.image_id)[1]}-${var.talos_image.platform}-${var.talos_image.arch}.img"
  file_name_update = "${var.talos_image.image_filename_prefix}-${split("_",local.update_image_id)[0]}-${split("_", local.update_image_id)[1]}-${var.talos_image.platform}-${var.talos_image.arch}.img"
  url = "${var.talos_image.factory_url}/image/${split("_",local.image_id)[0]}/${split("_", local.image_id)[1]}/${var.talos_image.platform}-${var.talos_image.arch}.raw.gz"
  url_update = "${var.talos_image.factory_url}/image/${split("_",local.update_image_id)[0]}/${split("_", local.update_image_id)[1]}/${var.talos_image.platform}-${var.talos_image.arch}.raw.gz"
}

resource "proxmox_virtual_environment_download_file" "this" {
  for_each = var.talos_nodes

  node_name    = each.value.host_node
  content_type = "iso"
  datastore_id = var.talos_image.datastore_id

  file_name               = each.value.update ? local.file_name_update : local.file_name
  url                     = each.value.update ? local.url_update : local.url
  decompression_algorithm = "gz"
  overwrite               = false
}

resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.talos_nodes

  node_name = each.value.host_node

  name        = each.key
  description = each.value.machine_type == "controlplane" ? "Talos Control Plane" : "Talos Worker"
  tags        = each.value.machine_type == "controlplane" ? ["k8s", "control-plane"] : ["k8s", "worker"]
  on_boot     = true
  vm_id       = each.value.vm_id

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  bios          = "seabios"

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }

  memory {
    dedicated = each.value.ram_dedicated
  }

  network_device {
    bridge      = each.value.network.device
    mac_address = each.value.network.mac_address
    vlan_id     = each.value.network.vlan_id
  }

  disk {
    datastore_id = each.value.datastore_id
    interface    = "scsi0"
    iothread     = true
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    file_format  = "raw"
    size         = 20
    file_id      = proxmox_virtual_environment_download_file.this[each.key].id
  }

  boot_order = ["scsi0"]

  operating_system {
    type = "l26" # Linux Kernel 2.6 - 6.X.
  }

  initialization {
    datastore_id = each.value.datastore_id

    # Optional DNS Block.  Update Nodes with a list value to use.
    dynamic "dns" {
      for_each = try(each.value.network.dns, null) != null ? { "enabled" = each.value.network.dns } : {}
      content {
        servers = each.value.network.dns
      }
    }

    ip_config {
      ipv4 {
        address = each.value.network.dhcp ? "dhcp": "${each.value.network.ip}/${each.value.network.subnet_mask}"
        gateway = each.value.network.dhcp ? null : each.value.network.gateway
      }
    }
  }

  dynamic "hostpci" {
    for_each = each.value.igpu ? [1] : []
    content {
      # Passthrough iGPU
      device  = "hostpci0"
      mapping = "iGPU"
      pcie    = true
      rombar  = true
      xvga    = false
    }
  }
}
