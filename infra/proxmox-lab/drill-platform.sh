#!/usr/bin/env bash
set -euo pipefail

LOCAL_API_PORT="${LOCAL_API_PORT:-18080}"
EVENT_COUNT="${EVENT_COUNT:-25}"
QUEUE_NAME="${QUEUE_NAME:-events:queue}"

section() {
  echo
  echo "== $* =="
}

status() {
  section "Pods"
  kubectl get pods -o wide

  section "Deployments"
  kubectl get deploy

  section "Services"
  kubectl get svc
}

wait_deploy() {
  kubectl rollout status "deployment/$1" --timeout=180s
}

api_smoke() {
  section "API smoke test"

  kubectl port-forward service/api "${LOCAL_API_PORT}:8080" >/tmp/platform-drill-api-pf.log 2>&1 &
  PF_PID="$!"

  cleanup_pf() {
    kill "$PF_PID" >/dev/null 2>&1 || true
  }
  trap cleanup_pf RETURN

  for i in {1..30}; do
    if curl -fsS "http://127.0.0.1:${LOCAL_API_PORT}/healthz" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  curl -fsS "http://127.0.0.1:${LOCAL_API_PORT}/healthz"
  curl -fsS "http://127.0.0.1:${LOCAL_API_PORT}/readyz"

  EVENT_JSON="$(curl -fsS -X POST "http://127.0.0.1:${LOCAL_API_PORT}/events")"
  EVENT_ID="$(printf '%s' "$EVENT_JSON" | jq -r '.id')"

  echo "Created event: ${EVENT_ID}"
  curl -fsS "http://127.0.0.1:${LOCAL_API_PORT}/events/${EVENT_ID}"
  echo
}

kill_pod() {
  local app="$1"

  section "Deleting one ${app} pod"
  kubectl get pods -l "app=${app}" -o wide
  POD="$(kubectl get pods -l "app=${app}" -o jsonpath='{.items[0].metadata.name}')"

  echo "Deleting pod: ${POD}"
  kubectl delete pod "${POD}"

  section "Waiting for ${app} deployment recovery"
  wait_deploy "${app}"
  kubectl get pods -l "app=${app}" -o wide
}

queue_backlog() {
  section "Creating queue backlog"

  echo "Scaling worker to 0 so queued work accumulates..."
  kubectl scale deployment/worker --replicas=0
  wait_deploy worker || true

  for i in {1..30}; do
    WORKER_PODS="$(kubectl get pods -l app=worker --no-headers 2>/dev/null | wc -l)"
    if [ "$WORKER_PODS" = "0" ]; then
      break
    fi
    sleep 1
  done

  kubectl port-forward service/api "${LOCAL_API_PORT}:8080" >/tmp/platform-drill-api-pf.log 2>&1 &
  PF_PID="$!"

  cleanup_pf() {
    kill "$PF_PID" >/dev/null 2>&1 || true
  }
  trap cleanup_pf RETURN

  for i in {1..30}; do
    if curl -fsS "http://127.0.0.1:${LOCAL_API_PORT}/readyz" >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  echo "Posting ${EVENT_COUNT} events..."
  for i in $(seq 1 "${EVENT_COUNT}"); do
    curl -fsS -X POST "http://127.0.0.1:${LOCAL_API_PORT}/events" >/dev/null
  done

  echo "Redis queue length before worker recovery:"
  kubectl exec deploy/redis -- redis-cli LLEN "${QUEUE_NAME}" || true

  echo "Scaling worker back to 1..."
  kubectl scale deployment/worker --replicas=1
  wait_deploy worker

  echo "Waiting for queue to drain..."
  for i in {1..30}; do
    LEN="$(kubectl exec deploy/redis -- redis-cli LLEN "${QUEUE_NAME}" 2>/dev/null || echo unknown)"
    echo "queue_length=${LEN}"
    if [ "$LEN" = "0" ]; then
      break
    fi
    sleep 2
  done
}

case "${1:-}" in
  status)
    status
    ;;
  smoke)
    api_smoke
    ;;
  kill-api)
    kill_pod api
    api_smoke
    ;;
  kill-worker)
    kill_pod worker
    ;;
  kill-redis)
    kill_pod redis
    api_smoke
    ;;
  backlog)
    queue_backlog
    ;;
  all)
    status
    api_smoke
    kill_pod api
    kill_pod worker
    queue_backlog
    status
    ;;
  *)
    echo "Usage: $0 {status|smoke|kill-api|kill-worker|kill-redis|backlog|all}"
    exit 1
    ;;
esac
