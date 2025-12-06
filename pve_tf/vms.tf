module "k3s-masters" {
  source           = "./modules/vms"
  count            = var.k3s_masters_count

  cpu              = 4
  hostname         = "k3s-${var.k3s_master_first_host + count.index}"
  memory           = 3052
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

  cpu              = 4
  hostname         = "k3s-${var.k3s_worker_first_host + count.index}"
  memory           = 4096
  node_name        = var.node_name
  user_name        = var.user_name
  vm_id            = var.k3s_worker_first_host + count.index
  vm_name          = "k3s-${var.k3s_worker_first_host + count.index}"
  ssh_pub_key_path = "${var.home_folder}/.ssh/id_rsa.pub"
  hostpci = {
    device = "hostpci0"
    id     = "0000:0b:00.0"
  }
  disks = [
    {
      datastore_id = var.vm_images_datastore
      size         = 32
      interface    = "${var.disk_interface}0"
      iothread     = true
      import_from  = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
    },
    {
      datastore_id = var.vm_images_datastore
      size         = 40
      interface    = "${var.disk_interface}1"
      iothread     = true
    }
  ]
}

module "proxy" {
  source = "./modules/vms"

  cpu              = 2
  hostname         = "k3s-proxy"
  memory           = 2048
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

module "truenas" {
  source = "./modules/vms"

  cpu                = 2
  hostname           = "truenas"
  memory             = 6144
  node_name          = var.node_name
  user_name          = var.user_name
  vm_id              = 160
  vm_name            = "truenas"
  ssh_pub_key_path   = "${var.home_folder}/.ssh/id_rsa.pub"
  cloud_init_enabled = false
  disks = [
    {
      datastore_id = var.vm_images_datastore
      size         = 32
      interface    = "${var.disk_interface}0"
      iothread     = true
    }
  ]
  # the Host PCI passthrough does not work. Both scsi controller 08 and 09 share a PCI bus.
  # When passing through proxmox crashes. One option would be to use an external SCSI controller card.
  # for now I am passing the full disk to vm this way:
  # root@pve-node3:~# qm set 160 --scsi1 /dev/disk/by-id/ata-ST4000VX016-3CV104_WW63M2Y0
  # root@pve-node3:~# qm set 160 --scsi2 /dev/disk/by-id/ata-Samsung_SSD_870_EVO_500GB_S7EWNJ0WA31093V
  # hostpci = {
  #   device = "hostpci0"
  #   id     = "0000:09:00.0"
  # }
  cdrom = {
    file_id = "none" # "local:iso/TrueNAS-SCALE-25.10.0.1.iso"
    enabled = false
  }
}
