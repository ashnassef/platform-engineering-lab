variable "cluster_name" {
  type    = string
  default = "tf-k8s"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.cluster_name))
    error_message = "cluster_name must use lowercase letters, numbers, and hyphens only."
  }
}

variable "ssh_user" {
  type    = string
  default = "dev1"
}

variable "worker_count" {
  type    = number
  default = 2

  validation {
    condition     = var.worker_count >= 1
    error_message = "worker_count must be at least 1."
  }
}

variable "control_vmid" {
  type    = number
  default = 111
}

variable "worker_start_vmid" {
  type    = number
  default = 112
}

variable "vm_bridge" {
  type    = string
  default = "vmbr1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "lab_subnet" {
  type    = string
  default = "10.0.0.0/24"

  validation {
    condition     = can(cidrhost(var.lab_subnet, 1))
    error_message = "lab_subnet must be a valid CIDR block."
  }
}

variable "gateway_host_number" {
  type    = number
  default = 1
}

variable "control_host_number" {
  type    = number
  default = 91
}

variable "worker_start_host_number" {
  type    = number
  default = 92
}

variable "control_cores" {
  type    = number
  default = 2
}

variable "control_memory" {
  type    = number
  default = 4096
}

variable "worker_cores" {
  type    = number
  default = 3
}

variable "worker_memory" {
  type    = number
  default = 8192
}
