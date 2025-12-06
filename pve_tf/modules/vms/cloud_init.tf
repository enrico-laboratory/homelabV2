data "local_file" "ssh_public_key" {
  filename = var.ssh_pub_key_path
}

resource "proxmox_virtual_environment_file" "user_data_cloud_config" {
  content_type = "snippets"
  datastore_id = var.snippets_datastore
  node_name    = var.node_name

  source_raw {
    data = <<-EOF
    #cloud-config
    hostname: ${var.hostname}
    timezone: Europe/Amsterdam
    users:
      - default
      - name: ${var.user_name}
        groups:
          - sudo
        shell: /bin/bash
        ssh_authorized_keys:
          - ${trimspace(data.local_file.ssh_public_key.content)}
        sudo: ALL=(ALL) NOPASSWD:ALL
    package_update: true
    packages:
      - qemu-guest-agent
      - net-tools
      - curl
      - nfs-common
      - open-iscsi
    runcmd:
      - systemctl start qemu-guest-agent
      - echo "done" > /tmp/cloud-config.done
    EOF
    file_name = "user-data-cloud-config-${var.hostname}.yaml"
  }
}