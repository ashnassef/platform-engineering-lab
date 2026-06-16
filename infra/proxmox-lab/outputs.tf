output "ssh_user" {
  value = var.ssh_user
}

output "control_name" {
  value = local.control_name
}

output "control_ip" {
  value = split("/", local.vms[local.control_name].ip)[0]
}

output "worker_names" {
  value = local.worker_names
}

output "worker_ips" {
  value = [
    for name in local.worker_names : split("/", local.vms[name].ip)[0]
  ]
}
