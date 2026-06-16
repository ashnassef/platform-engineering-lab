variable "vm_disk_gb" {
  type    = number
  default = 64
}

variable "host_memory_reserve_mb" {
  type    = number
  default = 4096
}

variable "cpu_overcommit_ratio" {
  type    = number
  default = 2
}
