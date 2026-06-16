#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="/root/terraform/proxmox-lab"
APP_DIR="/root/platform-engineering-lab"

section() {
  echo
  echo "== $* =="
}

section "Shell syntax"
cd "$INFRA_DIR"

for file in \
  platformctl \
  deploy-platform.sh \
  bootstrap-k3s.sh \
  drill-platform.sh \
  view-platform.sh \
  validate-platform.sh
do
  if [ -f "$file" ]; then
    bash -n "$file"
    echo "OK: $file"
  fi
done

section "Terraform validation"
cd "$INFRA_DIR"
terraform fmt -check
terraform validate

section "Go formatting and tests"
cd "$APP_DIR"

GOFMT_CHANGED="$(gofmt -l app/cmd/api/main.go app/cmd/worker/main.go app/internal/event/event.go)"
if [ -n "$GOFMT_CHANGED" ]; then
  echo "ERROR: gofmt needed:"
  echo "$GOFMT_CHANGED"
  exit 1
fi

go test ./...

section "Kubernetes manifest client-side validation"
kubectl apply --dry-run=client -f "$APP_DIR/k8s/redis.yaml"
kubectl apply --dry-run=client -f "$APP_DIR/k8s/api.yaml"
kubectl apply --dry-run=client -f "$APP_DIR/k8s/worker.yaml"
kubectl apply --dry-run=client -f "$APP_DIR/k8s/monitoring.yaml"
kubectl apply --dry-run=client -f "$APP_DIR/k8s/ingress.yaml"

section "Platform status"
cd "$INFRA_DIR"
platformctl status

section "Smoke test"
platformctl smoke

section "Idempotency drill"
platformctl drill idempotency

section "Redis persistence drill"
platformctl drill redis-persistence

section "Diagnosis"
platformctl diagnose

echo
echo "Validation complete."
