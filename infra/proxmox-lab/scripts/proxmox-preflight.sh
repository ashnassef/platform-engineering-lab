#!/usr/bin/env bash
set -euo pipefail

QUERY="$(cat)"

read_query() {
  python3 -c 'import json,sys; q=json.load(sys.stdin); print(q.get(sys.argv[1], sys.argv[2]))' "$1" "$2" <<< "$QUERY"
}

NODE="$(read_query node dev1)"
STORAGE="$(read_query storage local-lvm)"
REQUESTED_MEMORY_MB="$(read_query requested_memory_mb 0)"
REQUESTED_VCPUS="$(read_query requested_vcpus 0)"
REQUESTED_DISK_GB="$(read_query requested_disk_gb 0)"
DESIRED_VMIDS_CSV="$(read_query desired_vmids_csv '')"
HOST_MEMORY_RESERVE_MB="$(read_query host_memory_reserve_mb 4096)"
CPU_OVERCOMMIT_RATIO="$(read_query cpu_overcommit_ratio 2)"

NODE_JSON="$(pvesh get "/nodes/${NODE}/status" --output-format json)"
STORAGE_JSON="$(pvesh get "/nodes/${NODE}/storage/${STORAGE}/status" --output-format json)"
QEMU_JSON="$(pvesh get "/nodes/${NODE}/qemu" --output-format json)"

python3 - <<PY
import json

node = json.loads('''${NODE_JSON}''')
storage = json.loads('''${STORAGE_JSON}''')
vms = json.loads('''${QEMU_JSON}''')

requested_memory_mb = int("${REQUESTED_MEMORY_MB}")
requested_vcpus = int("${REQUESTED_VCPUS}")
requested_disk_gb = int("${REQUESTED_DISK_GB}")
desired_vmids = {int(x) for x in "${DESIRED_VMIDS_CSV}".split(",") if x}
reserve_mb = int("${HOST_MEMORY_RESERVE_MB}")
cpu_overcommit = int("${CPU_OVERCOMMIT_RATIO}")

memory_free_mb = node["memory"]["free"] // 1024 // 1024
memory_available_mb = max(0, memory_free_mb - reserve_mb)

storage_available_gb = storage["avail"] // 1024 // 1024 // 1024

cpu_threads = int(node["cpuinfo"]["cpus"])
vcpu_limit = cpu_threads * cpu_overcommit

existing_running_matching_memory_mb = 0
existing_matching_disk_gb = 0
other_running_vcpus = 0

for vm in vms:
    vmid = int(vm.get("vmid", -1))
    status = vm.get("status")

    if vmid in desired_vmids:
        if status == "running":
            existing_running_matching_memory_mb += vm.get("maxmem", 0) // 1024 // 1024
        existing_matching_disk_gb += vm.get("maxdisk", 0) // 1024 // 1024 // 1024
    elif status == "running":
        other_running_vcpus += int(vm.get("cpus", 0))

net_new_memory_mb = max(0, requested_memory_mb - existing_running_matching_memory_mb)
net_new_disk_gb = max(0, requested_disk_gb - existing_matching_disk_gb)
vcpu_after_apply = other_running_vcpus + requested_vcpus

ok = (
    net_new_memory_mb <= memory_available_mb
    and net_new_disk_gb <= storage_available_gb
    and vcpu_after_apply <= vcpu_limit
)

message = (
    f"net_new_memory={net_new_memory_mb}MB / available_memory={memory_available_mb}MB; "
    f"net_new_disk={net_new_disk_gb}GB / available_storage={storage_available_gb}GB; "
    f"vcpu_after_apply={vcpu_after_apply} / vcpu_limit={vcpu_limit}"
)

print(json.dumps({
    "ok": str(ok).lower(),
    "message": message
}))
PY
