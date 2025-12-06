resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "import"
  datastore_id = var.iso_datastore
  node_name    = var.node_name
  url          = var.jammy_image.url
  file_name    = var.jammy_image.file_name
}

