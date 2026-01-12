variable "node_name" {
  type    = string
  default = "pve-node3"
}

### VMS
variable "k3s_masters_count" {
  type = number
  default = 1
}

variable "k3s_master_first_host" {
  type = number
  default = 101
}

variable "k3s_workers_count" {
  type = number
  default = 3
}

variable "k3s_worker_first_host" {
  type = number
  default = 111
}

variable "user_name" {
  type = string
}

variable "ssh_pub_key_path" {
  type = string                     # The type of the variable, in this case a string
  default = ".ssh/id_rsa.pub"
}

variable "disk_interface" {
  default = "scsi"
}
variable "home_folder" {}

### Storage
variable "iso_datastore" {
  type    = string
  default = "local"
}

variable "snippets_datastore" {
  type    = string
  default = "local"
}

variable "vm_images_datastore" {
  type    = string
  default = "vmimages"
}

variable "jammy_image" {
  type = object({
    url       = string
    file_name = string
  })
  default = {
    url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    # need to rename the file to *.qcow2 to indicate the actual file format for import
    file_name = "jammy-server-cloudimg-amd64.qcow2"
  }

}
### ACME
variable "acme_email" {
  type        = string
  description = "email for the acme account creation"
}

variable "cf_account_id" {
  type        = string
  description = "CF_Account_ID"
}

variable "cf_token" {
  type        = string
  description = "CF_Token"
}

variable "cf_zone_id" {
  type        = string
  description = "CF_Zone_ID"
}