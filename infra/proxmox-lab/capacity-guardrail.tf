data "external" "proxmox_preflight" {
  program = ["bash", "${path.module}/scripts/proxmox-preflight.sh"]

  query = {
    node                   = "dev1"
    storage                = "local-lvm"
    requested_memory_mb    = tostring(sum([for vm in values(local.vms) : vm.memory]))
    requested_vcpus        = tostring(sum([for vm in values(local.vms) : vm.cores]))
    requested_disk_gb      = tostring(length(local.vms) * var.vm_disk_gb)
    desired_vmids_csv      = join(",", [for vm in values(local.vms) : tostring(vm.vm_id)])
    host_memory_reserve_mb = tostring(var.host_memory_reserve_mb)
    cpu_overcommit_ratio   = tostring(var.cpu_overcommit_ratio)
  }
}

resource "terraform_data" "capacity_guardrail" {
  input = {
    ok = data.external.proxmox_preflight.result.ok
  }

  lifecycle {
    precondition {
      condition     = data.external.proxmox_preflight.result.ok == "true"
      error_message = data.external.proxmox_preflight.result.message
    }
  }
}
