# Operations

This document summarizes the verified operator workflow for the lab.

## `platformctl` Role

`infra/proxmox-lab/platformctl` is the main operator interface. It consolidates:

- provisioning
- validation
- status inspection
- deployment
- scaling
- recovery
- drills
- safe teardown

Exact command surface verified in the staged source:

- `./platformctl verify`
- `./platformctl capacity`
- `./platformctl shape check --workers <count>`
- `./platformctl build [--resume|--force]`
- `./platformctl deploy`
- `./platformctl undeploy`
- `./platformctl smoke`
- `./platformctl status [full]`
- `./platformctl diagnose`
- `./platformctl repair`
- `./platformctl view`
- `./platformctl expose`
- `./platformctl scale workers <replicas>`
- `./platformctl drill {status|smoke|kill-api|kill-worker|kill-redis|backlog|idempotency|redis-persistence|drain-node|all}`
- `./platformctl destroy`

## Workflow Summary

### Build

`./platformctl build` drives Terraform apply, waits for SSH and apt readiness, boots k3s, and finishes with ready nodes.

### Deploy

`./platformctl deploy` applies the Kubernetes workload set from `app/k8s` and the observability manifests.

### Status

`./platformctl status` gives a concise health summary. `./platformctl status full` prints the raw state, Terraform outputs, nodes, pods, services, Redis queue length, and Prometheus targets.

### Smoke

`./platformctl smoke` runs the lightweight application checks through the drill helper.

### Capacity

`./platformctl capacity` reports host, Proxmox, Terraform, and Kubernetes headroom.

### Scaling

`./platformctl scale workers <replicas>` changes the worker deployment replica count and waits for rollout completion when replicas are nonzero.

### Diagnosis

`./platformctl diagnose` inspects host readiness, Terraform state, VM reachability, SSH, apt locks, k3s services, Kubernetes readiness, pods, recent events, queue state, Redis persistence, and monitoring targets.

### Repair

`./platformctl repair` performs conservative service recovery steps without destroying the lab.

### View and Expose

`./platformctl view` starts the local dashboard and port-forward view.

`./platformctl expose` prints and tests the ingress endpoint for `platform.local`.

### Drills

The drill commands demonstrate failure and recovery behavior:

- `./platformctl drill idempotency`
- `./platformctl drill redis-persistence`
- `./platformctl drill drain-node`
- `./platformctl drill backlog`
- `./platformctl drill kill-api`
- `./platformctl drill kill-worker`
- `./platformctl drill kill-redis`

## Verified Demonstrations

- status and smoke checks
- worker backlog and scaling
- pod deletion and recovery
- Redis persistence across pod restart
- readiness failure when Redis is unavailable
- safe node drain that avoids the Redis local-path PVC node
- idempotency behavior

## Safe-Drain Constraint

The Redis deployment uses a local-path PVC, so the drain drill intentionally avoids the node hosting Redis. Draining that node would interfere with the persistent volume attachment rather than demonstrating safe workload recovery.

## Evidence Collection

The lab relies on before-and-after evidence rather than blind changes:

- `platformctl status` and `platformctl status full`
- `kubectl get`, `kubectl describe`, and `kubectl rollout status`
- Redis queue depth checks
- Prometheus target checks
- drill-specific request/response evidence for idempotency and recovery
- logs printed by `platformctl diagnose`
