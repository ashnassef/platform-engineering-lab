locals {
  lab_prefix_length = split("/", var.lab_subnet)[1]
  gateway_ip        = cidrhost(var.lab_subnet, var.gateway_host_number)

  control_name = "${var.cluster_name}-control"

  worker_names = [
    for i in range(var.worker_count) : "${var.cluster_name}-worker-${i + 1}"
  ]

  control_vm = {
    (local.control_name) = {
      vm_id  = var.control_vmid
      ip     = "${cidrhost(var.lab_subnet, var.control_host_number)}/${local.lab_prefix_length}"
      cores  = var.control_cores
      memory = var.control_memory
    }
  }

  worker_vms = {
    for i in range(var.worker_count) : "${var.cluster_name}-worker-${i + 1}" => {
      vm_id  = var.worker_start_vmid + i
      ip     = "${cidrhost(var.lab_subnet, var.worker_start_host_number + i)}/${local.lab_prefix_length}"
      cores  = var.worker_cores
      memory = var.worker_memory
    }
  }

  vms = merge(local.control_vm, local.worker_vms)
}

resource "proxmox_virtual_environment_vm" "lab" {
  depends_on = [terraform_data.capacity_guardrail]

  for_each = local.vms

  name      = each.key
  vm_id     = each.value.vm_id
  node_name = "dev1"

  clone {
    vm_id = 100
    full  = true
  }

  agent {
    enabled = true
  }

  bios            = "ovmf"
  machine         = "q35"
  started         = true
  on_boot         = true
  stop_on_destroy = true

  efi_disk {
    datastore_id      = "local-lvm"
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = false
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = each.value.ip
        gateway = local.gateway_ip
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.ssh_user
      keys     = [trimspace(file("/root/.ssh/id_ed25519.pub"))]
    }
  }
}
