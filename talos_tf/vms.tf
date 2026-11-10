resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.nodes

  name      = each.key
  node_name = var.node_name
  vm_id     = each.value.vm_id
  on_boot   = true
  started   = true

  machine       = "q35"
  scsi_hardware = "virtio-scsi-single"
  # empty disk is skipped on first boot, so the ISO boots; after install the disk wins
  boot_order = ["scsi0", "ide3"]

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cpu
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.vm_images_datastore
    interface    = "scsi0"
    size         = each.value.disk_size
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide3"
  }

  network_device {
    bridge = var.network_bridge
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    # the ISO stays attached after install; do not churn on it
    ignore_changes = [cdrom]
  }
}
