variable "vm_name" {
  type = string
}

variable "node_name" {
  type = string
}

variable "cloud_init_datastore_id" {
  type    = string
  default = "local-lvm"
}

variable "ip_subnet" {
  type        = string
  default     = "192.168.100"
  description = "first 3 octect 192.168.100"
}

variable "vm_id" {
  type = number
}

variable "gateway" {
  type    = string
  default = "192.168.100.1"
}

variable "snippets_datastore" {
  type    = string
  default = "local"
}

variable "vm_image_datastore" {
  type    = string
  default = "vmimages"
}


variable "disks" {
  description = "List of disks to attach to the VM"
  type = list(object({
    datastore_id = string
    size         = number
    interface    = string
    iothread     = optional(bool)
    import_from  = optional(string)
    file_id      = optional(string)
  }))
}

variable "cdrom" {
  description = "CDROM configuration for the VM"
  type = object({
    enabled = bool
    file_id = string
  })
  default = null
}

variable "network_device" {
  type    = string
  default = "vmbr0"
}

variable "ssh_pub_key_path" {
  type = string # The type of the variable, in this case a string
}

variable "hostname" {
  type = string
}

variable "user_name" {
  type = string
}

variable "cpu_type" {
  type    = string
  default = "x86-64-v2-AES"
}

variable "machine_type" {
  type    = string
  default = "q35"
}

variable "hostpci" {
  type = object({
    device   = string
    id       = string
    pcie     = optional(bool)
    rom_file = optional(string)
    xvga     = optional(bool)
    rombar   = optional(bool)
  })
  default = null
}

variable "worker_vm_id_with_gpu" {
  type    = number
  default = 113
}

variable "cloud_init_enabled" {
  type        = bool
  default     = true
  description = "Enable the initialization block for cloud-init"
}

variable "dns" {
  type = object({
    domain  = string
    servers = list(string)
  })
  default = {
    domain  = "enricoruggeri.com"
    servers = ["8.8.8.8", "8.8.4.4"]
  }
}

variable "started" {
  type    = bool
  default = true
}

variable "on_boot" {
  type    = bool
  default = false
}

variable "vm_gpu" {
  type = object({
    id = number
    memory = number
    cpu = number
  })
  default = {
    id     = 0
    memory = 0
    cpu    = 0
  }
}

variable "memory_default" {
    type    = number
    default = 2048
}

variable "cpu_default" {
    type    = number
    default = 4
}
