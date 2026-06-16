#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/root/platform-engineering-lab"
BACKUP_DIR="/mnt/temp/platform-demo/platform-lab-backup-2026-05-31"
INGRESS_NGINX_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/baremetal/deploy.yaml"

cd /root/terraform/proxmox-lab

CONTROL_IP="$(terraform output -raw control_ip)"

mapfile -t WORKER_IPS < <(
  terraform output -json worker_ips | jq -r '.[]'
)

NODE_IPS=("$CONTROL_IP" "${WORKER_IPS[@]}")

manifest_image() {
  local manifest="$1"

  awk '
    /^[[:space:]]*image:[[:space:]]*/ {
      print $2
      exit
    }
  ' "$manifest"
}

API_IMAGE="$(manifest_image "${APP_DIR}/k8s/api.yaml")"
WORKER_IMAGE="$(manifest_image "${APP_DIR}/k8s/worker.yaml")"

[ -n "$API_IMAGE" ] || {
  echo "ERROR: Could not determine API image from ${APP_DIR}/k8s/api.yaml"
  exit 1
}

[ -n "$WORKER_IMAGE" ] || {
  echo "ERROR: Could not determine worker image from ${APP_DIR}/k8s/worker.yaml"
  exit 1
}

verify_image_on_node() {
  local ip="$1"
  local image="$2"

  if ssh dev1@"${ip}" "sudo k3s ctr -n k8s.io images ls | grep -F -- '${image}' >/dev/null"; then
    echo "  OK: ${image}"
    return 0
  fi

  echo
  echo "ERROR: Expected image was not imported on node ${ip}:"
  echo "  ${image}"
  echo
  echo "Images currently present on ${ip}:"
  ssh dev1@"${ip}" "sudo k3s ctr -n k8s.io images ls | grep -E 'platform-engineering-lab|REF' || true"
  echo
  echo "This usually means the image tarball tag does not match the Kubernetes manifest tag."
  exit 1
}

echo "Expected app images:"
echo "  API:    ${API_IMAGE}"
echo "  Worker: ${WORKER_IMAGE}"

echo
echo "Importing app images into k3s nodes..."

for ip in "${NODE_IPS[@]}"; do
  echo
  echo "Importing images on ${ip}..."

  scp "${BACKUP_DIR}/platform-engineering-lab-api.tar" dev1@"${ip}":/tmp/
  scp "${BACKUP_DIR}/platform-engineering-lab-worker.tar" dev1@"${ip}":/tmp/

  ssh dev1@"${ip}" "sudo k3s ctr -n k8s.io images import /tmp/platform-engineering-lab-api.tar"
  ssh dev1@"${ip}" "sudo k3s ctr -n k8s.io images import /tmp/platform-engineering-lab-worker.tar"

  echo "Verifying imported image tags on ${ip}..."
  verify_image_on_node "$ip" "$API_IMAGE"
  verify_image_on_node "$ip" "$WORKER_IMAGE"
done

echo
echo "Installing ingress-nginx if needed..."

if ! kubectl -n ingress-nginx get deployment ingress-nginx-controller >/dev/null 2>&1; then
  kubectl apply -f "${INGRESS_NGINX_URL}"
fi

kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=300s

echo "Pinning ingress-nginx NodePorts..."

kubectl -n ingress-nginx patch service ingress-nginx-controller \
  --type='json' \
  -p='[
    {"op":"replace","path":"/spec/ports/0/nodePort","value":30080},
    {"op":"replace","path":"/spec/ports/1/nodePort","value":30443}
  ]' >/dev/null

echo
echo "Applying platform manifests..."

kubectl apply -f "${APP_DIR}/k8s/redis.yaml"
kubectl apply -f "${APP_DIR}/k8s/api.yaml"
kubectl apply -f "${APP_DIR}/k8s/worker.yaml"

echo
echo "Applying monitoring config..."

kubectl create configmap prometheus-config \
  --from-file=prometheus.yml="${APP_DIR}/observability/prometheus/prometheus.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap grafana-datasources \
  --from-file=prometheus.yml="${APP_DIR}/observability/grafana/provisioning/datasources/prometheus.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap grafana-dashboard-providers \
  --from-file=dashboards.yml="${APP_DIR}/observability/grafana/provisioning/dashboards/dashboards.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create configmap grafana-dashboards \
  --from-file=platform-lab.json="${APP_DIR}/observability/grafana/dashboards/platform-lab.json" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f "${APP_DIR}/k8s/monitoring.yaml"
kubectl apply -f "${APP_DIR}/k8s/ingress.yaml"

echo
echo "Waiting for rollouts..."

kubectl rollout status deployment/redis --timeout=180s
kubectl rollout status deployment/api --timeout=180s
kubectl rollout status deployment/worker --timeout=180s
kubectl rollout status deployment/prometheus --timeout=180s
kubectl rollout status deployment/grafana --timeout=180s

echo
echo "Platform deployed."

echo
echo "Pods:"
kubectl get pods -o wide

echo
echo "Services:"
kubectl get svc

echo
echo "Ingress:"
kubectl get ingress

echo
echo "API ingress test:"
echo "  curl -H 'Host: platform.local' http://${CONTROL_IP}:30080/healthz"
