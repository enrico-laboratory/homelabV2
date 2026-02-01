module "k3s-masters" {
  source = "./modules/vms"
  count  = var.k3s_masters_count

  on_boot          = true
  started          = true
  cpu_default      = 4
  hostname         = "k3s-${var.k3s_master_first_host + count.index}"
  memory_default   = 4096
  node_name        = var.node_name
  user_name        = var.user_name
  vm_id            = var.k3s_master_first_host + count.index
  vm_name          = "k3s-${var.k3s_master_first_host + count.index}"
  ssh_pub_key_path = "${var.home_folder}/.ssh/id_rsa.pub"
  hostpci          = null
  disks = [
    {
      datastore_id = var.vm_images_datastore
      size         = 32
      interface    = "${var.disk_interface}0"
      iothread     = true
      import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    }
  ]
}

module "k3s-workers" {
  source = "./modules/vms"
  count  = var.k3s_workers_count

  on_boot        = true
  started        = true
  cpu_default    = 4
  hostname       = "k3s-${var.k3s_worker_first_host + count.index}"
  memory_default = 4096
  vm_gpu = {
    id     = 113
    memory = 24576
    cpu    = 8
  }
  node_name        = var.node_name
  user_name        = var.user_name
  vm_id            = var.k3s_worker_first_host + count.index
  vm_name          = "k3s-${var.k3s_worker_first_host + count.index}"
  ssh_pub_key_path = "${var.home_folder}/.ssh/id_rsa.pub"
  hostpci = {
    device   = "hostpci0"
    id       = "0000:0b:00.0"
    pcie     = true
    xvga     = false
    rombar   = true
    rom_file = "gtx970.rom"
  }
  disks = [
    {
      datastore_id = var.vm_images_datastore
      size         = 48
      interface    = "${var.disk_interface}0"
      iothread     = true
      import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    }
  ]
}

module "proxy" {
  source = "./modules/vms"

  on_boot          = true
  started          = true
  cpu_default      = 2
  hostname         = "k3s-proxy"
  memory_default   = 2048
  node_name        = var.node_name
  user_name        = var.user_name
  vm_id            = 140
  vm_name          = "k3s-proxy"
  ssh_pub_key_path = "${var.home_folder}/.ssh/id_rsa.pub"
  hostpci          = null
  disks = [
    {
      datastore_id = var.vm_images_datastore
      size         = 32
      interface    = "${var.disk_interface}0"
      iothread     = true
      import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    }
  ]
}

module "nas" {
  source = "./modules/vms"

  on_boot          = true
  started          = true
  cpu_default      = 2
  hostname         = "nas"
  memory_default   = 4096
  node_name        = var.node_name
  user_name        = var.user_name
  vm_id            = 160
  vm_name          = "nas"
  ssh_pub_key_path = "${var.home_folder}/.ssh/id_rsa.pub"
  hostpci          = null
  disks = [
    {
      datastore_id = var.vm_images_datastore
      size         = 32
      interface    = "${var.disk_interface}0"
      iothread     = false
      import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    }
  ]
  # the Host PCI passthrough does not work. Both scsi controller 08 and 09 share a PCI bus.
  #   # When passing through proxmox crashes. One option would be to use an external SCSI controller card.
  #   # for now I am passing the full disk to vm this way:
  #   # root@pve-node3:~# qm set 160 --scsi1 /dev/disk/by-id/ata-ST4000VX016-3CV104_WW63M2Y0
  #   # root@pve-node3:~# qm set 160 --scsi2 /dev/disk/by-id/ata-Samsung_SSD_870_EVO_500GB_S7EWNJ0WA31093V
  #   # hostpci = {
  #   #   device = "hostpci0"
  #   #   id     = "0000:09:00.0"
  #   # }
}

resource "proxmox_virtual_environment_vm" "win_11" {
  node_name = var.node_name

  on_boot = false
  vm_id   = 201
  name    = "win-11"
  started = false
  cpu {
    cores   = 4
    type    = "x86-64-v3"
    sockets = 1
    flags   = ["+aes"]
  }
  memory {
    dedicated = 8192
    floating  = 0
  }
  bios = "ovmf"
  vga {
    type = "none"
  }
  machine = "q35"
  efi_disk {
    datastore_id      = var.vm_images_datastore
    type              = "4m"
    pre_enrolled_keys = true
  }
  tpm_state {
    datastore_id = var.vm_images_datastore
    version      = "v2.0"
  }
  hostpci {
    device   = "hostpci0"
    id       = "0000:0c:00.0"
    pcie     = true
    rom_file = "patched_gpu.rom"
    xvga     = true
    rombar   = true
  }
  hostpci {
    device = "hostpci1"
    id     = "0000:04:00.0"
    rombar = true
  }
  hostpci {
    device = "hostpci2"
    id     = "0000:08:00.1"
    rombar = true
  }
  network_device {
    bridge = "vmbr0"
    model  = "e1000"
  }
  scsi_hardware = "virtio-scsi-single"
}

# module "truenas" {
#   source = "./modules/vms"
#
#   on_boot            = false
#   started            = true
#   cpu_default        = 1
#   hostname           = "truenas"
#   memory_default     = 12288
#   node_name          = var.node_name
#   user_name          = var.user_name
#   vm_id              = 160
#   vm_name            = "truenas"
#   ssh_pub_key_path   = "${var.home_folder}/.ssh/id_rsa.pub"
#   cloud_init_enabled = false
#   disks = [
#     {
#       datastore_id = var.vm_images_datastore
#       size         = 32
#       interface    = "virtio0"
#       iothread     = true
#     }
#   ]
#   # the Host PCI passthrough does not work. Both scsi controller 08 and 09 share a PCI bus.
#   # When passing through proxmox crashes. One option would be to use an external SCSI controller card.
#   # for now I am passing the full disk to vm this way:
#   # root@pve-node3:~# qm set 160 --scsi1 /dev/disk/by-id/ata-ST4000VX016-3CV104_WW63M2Y0
#   # root@pve-node3:~# qm set 160 --scsi2 /dev/disk/by-id/ata-Samsung_SSD_870_EVO_500GB_S7EWNJ0WA31093V
#   # hostpci = {
#   #   device = "hostpci0"
#   #   id     = "0000:09:00.0"
#   # }
#   cdrom = {
#     # file_id = "none"
#     # enabled = false
#     file_id = "local:iso/TrueNAS-SCALE-25.04.2.6.iso"
#     enabled = true
#   }
# }

# module "ai" {
#   source = "./modules/vms"
#
#   cpu                   = 4
#   hostname              = "ai"
#   memory                = 3052
#   node_name             = var.node_name
#   user_name             = var.user_name
#   vm_id                 = 150
#   vm_name               = "ai"
#   ssh_pub_key_path      = "${var.home_folder}/.ssh/id_rsa.pub"
#   worker_vm_id_with_gpu = 150
#   machine_type          = "q35"
#   hostpci = {
#     device   = "hostpci0"
#     id       = "0000:0b:00.0"
#     pcie     = true
#     rom_file = "patched_gpu.rom"
#     xvga     = false
#     rombar   = true
#   }
#   disks = [
#     {
#       datastore_id = var.vm_images_datastore
#       size         = 32
#       interface    = "${var.disk_interface}0"
#       iothread     = true
#       import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
#     }
#   ]
# }


