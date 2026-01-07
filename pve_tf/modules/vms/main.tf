resource "proxmox_virtual_environment_vm" "ubuntu_vm" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id
  started   = var.started
  on_boot   = var.on_boot
  machine = var.machine_type
  agent {
    enabled = true
  }

  cpu {
    cores = var.cpu
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory
  }

  dynamic "initialization" {
    for_each = var.cloud_init_enabled ? [1] : []
    content {
      datastore_id = var.cloud_init_datastore_id
      dns {
        servers = var.dns.servers
      }
      ip_config {
        ipv4 {
          address = "${var.ip_subnet}.${var.vm_id}/24"
          gateway = var.gateway
        }
      }

      user_data_file_id = proxmox_virtual_environment_file.user_data_cloud_config.id
    }
  }

  dynamic "disk" {
    for_each = var.disks
    content {
      datastore_id = disk.value.datastore_id
      size         = disk.value.size
      interface    = disk.value.interface
      iothread     = lookup(disk.value, "iothread", null)
      import_from  = lookup(disk.value, "import_from", null)
      file_id      = lookup(disk.value, "file_id", null)
    }
  }

  dynamic "cdrom" {
    for_each = var.cdrom != null ? [var.cdrom] : []
    content {
      enabled = var.cdrom.enabled
      file_id = var.cdrom.file_id
    }
  }

  dynamic "hostpci" {
    for_each = (var.vm_id == var.worker_vm_id_with_gpu && var.hostpci != null) ? [var.hostpci] : []
    content {
      device   = var.hostpci.device
      id       = var.hostpci.id
      pcie     = var.hostpci.pcie
      rom_file = var.hostpci.rom_file
      xvga     = var.hostpci.xvga
      rombar   = var.hostpci.rombar
    }
  }

  network_device {
    bridge = var.network_device
  }
}