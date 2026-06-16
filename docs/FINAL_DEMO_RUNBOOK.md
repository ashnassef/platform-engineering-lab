# Final Platform Demo Runbook

## Purpose

This runbook describes the validation flow for the local Proxmox/k3s platform lab.

## Platform components

- Terraform-managed Proxmox lab VMs on one physical Proxmox host
- Three Ubuntu 24.04 VMs
- k3s Kubernetes cluster
- API deployment
- Worker deployment
- Redis deployment with local-path PVC-backed AOF persistence
- ingress-nginx API route
- Prometheus metrics collection
- Grafana dashboard surface
- platformctl operator command

## Primary validation sequence

Run from the repository root:

    cd infra/proxmox-lab

Then run:

    ./platformctl status
    ./platformctl expose
    ./platformctl smoke
    ./platformctl drill idempotency
    ./platformctl drill redis-persistence
    ./platformctl scale workers 3
    ./platformctl drill drain-node
    ./platformctl scale workers 1
    ./platformctl diagnose

## Command reference

### platformctl status

Checks:

- Terraform VM state
- Terraform output IPs
- kubeconfig availability
- Kubernetes API reachability
- node readiness
- deployment readiness
- service existence
- API health/readiness
- API ingress route
- Redis queue depth
- Redis PVC existence
- Redis AOF persistence
- Prometheus target health

### platformctl expose

Prints and tests the API ingress route.

Live-lab example:

    curl -H 'Host: platform.local' http://10.0.0.91:30080/healthz

### platformctl smoke

Checks:

- API health
- API readiness
- event creation
- event lookup

### platformctl drill idempotency

Checks:

- API deployment rollout state
- Worker deployment rollout state
- expected runtime image tags
- ingress availability
- duplicate POST behavior with the same Idempotency-Key
- X-Idempotent-Replay: true on replay

### platformctl drill redis-persistence

Checks:

- worker scale-down
- pending queue item creation
- Redis pod restart
- queue item survival after restart
- worker restoration

### platformctl drill drain-node

Checks:

- worker-node drain behavior
- pod rescheduling
- node uncordon behavior
- workload recovery
- safe drain avoidance of the Redis local-path PVC node

### platformctl diagnose

Checks:

- host prerequisites
- Terraform validation
- VM state
- SSH reachability
- apt/dpkg lock state
- k3s service state
- Kubernetes node state
- deployment readiness
- pod state
- recent Kubernetes events
- Redis queue state
- Redis persistence state
- Prometheus target health

## Expected final state

- platformctl status is green
- platformctl smoke passes
- platformctl drill idempotency passes
- platformctl drill redis-persistence passes
- platformctl drill drain-node passes
- platformctl diagnose completes without hard failures
