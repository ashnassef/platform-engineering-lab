#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

SSH_USER="$(terraform output -raw ssh_user)"
CONTROL_NAME="$(terraform output -raw control_name)"
CONTROL_IP="$(terraform output -raw control_ip)"
K3S_URL="https://${CONTROL_IP}:6443"

mapfile -t WORKER_NAMES < <(terraform output -json worker_names | jq -r '.[]')
mapfile -t WORKER_IPS < <(terraform output -json worker_ips | jq -r '.[]')

SSH_KNOWN_HOSTS="/root/.ssh/proxmox-lab-known_hosts"
SSH_OPTS=(
  -o UserKnownHostsFile="${SSH_KNOWN_HOSTS}"
  -o StrictHostKeyChecking=accept-new
)

install_lab_ssh_config() {
  mkdir -p /root/.ssh
  touch "${SSH_KNOWN_HOSTS}"
  chmod 700 /root/.ssh
  chmod 600 "${SSH_KNOWN_HOSTS}"

  if ! grep -q "Host 10.0.0.*" /root/.ssh/config 2>/dev/null; then
    cat >> /root/.ssh/config <<EOF

Host 10.0.0.*
    UserKnownHostsFile ${SSH_KNOWN_HOSTS}
    StrictHostKeyChecking accept-new
EOF
    chmod 600 /root/.ssh/config
  fi
}

run() {
  local host="$1"
  shift
  ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" "$@"
}

echo "Clearing stale SSH host keys..."
install_lab_ssh_config
mkdir -p /root/.ssh
touch "${SSH_KNOWN_HOSTS}"
for file in "${SSH_KNOWN_HOSTS}" /root/.ssh/known_hosts; do
  touch "$file"
  ssh-keygen -f "$file" -R "$CONTROL_IP" >/dev/null 2>&1 || true

  for ip in "${WORKER_IPS[@]}"; do
    ssh-keygen -f "$file" -R "$ip" >/dev/null 2>&1 || true
  done
done

echo "Checking SSH and sudo..."
run "$CONTROL_IP" "sudo -n true"
for ip in "${WORKER_IPS[@]}"; do
  run "$ip" "sudo -n true"
done

echo "Ensuring curl exists..."
run "$CONTROL_IP" "sudo apt-get update && sudo apt-get install -y curl"
for ip in "${WORKER_IPS[@]}"; do
  run "$ip" "sudo apt-get update && sudo apt-get install -y curl"
done

echo "Cleaning old k3s if present..."
for ip in "${WORKER_IPS[@]}"; do
  run "$ip" "if [ -x /usr/local/bin/k3s-agent-uninstall.sh ]; then sudo /usr/local/bin/k3s-agent-uninstall.sh; fi"
done
run "$CONTROL_IP" "if [ -x /usr/local/bin/k3s-uninstall.sh ]; then sudo /usr/local/bin/k3s-uninstall.sh; fi"

echo "Installing k3s server on ${CONTROL_NAME}..."
run "$CONTROL_IP" "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC='server --node-ip ${CONTROL_IP} --advertise-address ${CONTROL_IP} --tls-san ${CONTROL_IP} --write-kubeconfig-mode 644 --disable traefik' sh -"

echo "Getting node token..."
TOKEN="$(run "$CONTROL_IP" "sudo cat /var/lib/rancher/k3s/server/node-token" | tr -d '\r\n')"

echo "Installing workers..."
for i in "${!WORKER_IPS[@]}"; do
  ip="${WORKER_IPS[$i]}"
  name="${WORKER_NAMES[$i]}"
  echo "Installing ${name} at ${ip}..."
  run "$ip" "curl -sfL https://get.k3s.io | K3S_URL='${K3S_URL}' K3S_TOKEN='${TOKEN}' INSTALL_K3S_EXEC='agent --node-ip ${ip}' sh -"
done

EXPECTED_COUNT="$((1 + ${#WORKER_IPS[@]}))"

echo "Waiting for nodes..."
for i in {1..60}; do
  READY_COUNT="$(run "$CONTROL_IP" "sudo k3s kubectl get nodes --no-headers 2>/dev/null | awk '\$2 == \"Ready\" {count++} END {print count+0}'" || echo 0)"
  echo "Ready nodes: ${READY_COUNT}/${EXPECTED_COUNT}"

  if [ "$READY_COUNT" = "$EXPECTED_COUNT" ]; then
    break
  fi

  sleep 5
done

echo "Labeling worker nodes..."
for name in "${WORKER_NAMES[@]}"; do
  run "$CONTROL_IP" "sudo k3s kubectl label node ${name} node-role.kubernetes.io/worker=worker --overwrite"
done

echo "Copying kubeconfig..."
mkdir -p /root/.kube
ssh "${SSH_OPTS[@]}" "${SSH_USER}@${CONTROL_IP}" "sudo cat /etc/rancher/k3s/k3s.yaml" \
  | sed "s/127.0.0.1/${CONTROL_IP}/g" > /root/.kube/config
chmod 600 /root/.kube/config

echo "Final node status:"
kubectl get nodes -o wide
