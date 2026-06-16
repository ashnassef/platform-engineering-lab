#!/usr/bin/env bash
set -euo pipefail

HOST_IP="$(hostname -I | awk '{print $1}')"

echo "Starting browser access port-forwards..."
echo
echo "API:        http://${HOST_IP}:18080"
echo "Prometheus: http://${HOST_IP}:19090"
echo "Grafana:    http://${HOST_IP}:13000"
echo
echo "Press Ctrl+C to stop."

kubectl port-forward --address 0.0.0.0 service/api 18080:8080 >/tmp/platform-api-view.log 2>&1 &
API_PID="$!"

kubectl port-forward --address 0.0.0.0 service/prometheus 19090:9090 >/tmp/platform-prometheus-view.log 2>&1 &
PROM_PID="$!"

kubectl port-forward --address 0.0.0.0 service/grafana 13000:3000 >/tmp/platform-grafana-view.log 2>&1 &
GRAFANA_PID="$!"

cleanup() {
  kill "$API_PID" "$PROM_PID" "$GRAFANA_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

wait
