resource "proxmox_vm_qemu" "k3s_vms" {
  for_each    = { for object in var.k3s : object.name => object }
  name        = "k3s-${each.key}"
  target_node = var.target_node
  clone       = var.template_name
  full_clone  = true
  vmid        = each.value.vmid
  onboot      = each.value.onboot

  # cpu_type = var.cpu_type
  sockets  = 1
  cores    = each.value.cores
  memory   = each.value.memory

  scsihw = "virtio-scsi-single"

  network {
    model  = "virtio"
    bridge = var.bridge
  }
  disks {
  scsi {
    scsi0 {
      disk {
        size = "2361393182K"
        storage = var.vm_storage
                  emulatessd = true
          iothread = false
          discard = true
          backup = true
          replicate = true
      }
    }
  }
}
bootdisk = "scsi0"

  skip_ipv6 = true

  ipconfig0    = "ip=192.168.100.${each.value.vmid}/24,gw=${var.gateway}"
  nameserver   = var.nameserver
  searchdomain = var.searchdomain
  ciupgrade    = true
  ciuser       = var.user.name
  sshkeys      = var.user.sshkeys
}

# resource "proxmox_cloud_init_disk" "ci" {
#   for_each = { for object in var.k3s : object.name => object }
#   name = object.key
#   pve_node = var.target_node
#   storage = var.iso_storage

#   meta_data = yamlencode({
#   instance_id    = sha1(local.vm_name)
#   local-hostname = local.vm_name

#   })
# }

variable "k3s" {
  type = list(object({
    name   = string
    vmid   = number
    cores  = number
    memory = number
    onboot = bool
  }))
}

variable "target_node" {
  type    = string
  default = "pve-node1"
}

variable "template_name" {
  type    = string
  default = "template-linux"
}
variable "iso_storage" {
  type    = string
  default = "truenas-iso-nfs"
}
variable "vm_storage" {
  type = string
  default = "vmimages"
}
variable "cpu_type" {
  type    = string
  default = "host"
}
variable "bridge" {
  type    = string
  default = "vmbr0"
}
variable "gateway" {
  type    = string
  default = "192.168.100.1"
}

variable "nameserver" {
  type    = string
  default = "8.8.4.4"
}
variable "searchdomain" {
  type    = string
}
variable "user" {
  type = object({
    name    = string
    sshkeys = string
  })
}