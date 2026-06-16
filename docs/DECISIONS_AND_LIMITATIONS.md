# Decisions and Limitations

This lab intentionally favors clarity, repeatability, and reviewability over completeness.

## Decisions

### k3s on local Proxmox

k3s on local Proxmox was a good fit because it let the lab demonstrate real Kubernetes operations, Terraform-driven VM lifecycle, and host-level recovery without requiring public-cloud infrastructure or a larger multi-host environment.

### Redis lists for the queue

Redis lists were sufficient for the demonstration because they make queue state easy to inspect, move, and reason about while still exercising backpressure, retries, and dead-letter handling.

### AOF plus PVC

AOF and a PVC were added so the lab could prove state survival across a Redis pod restart instead of presenting Redis as a purely ephemeral cache.

### `platformctl` consolidation

`platformctl` consolidates the operator workflow so build, deploy, status, smoke, scale, diagnose, repair, view, and drill behavior is discoverable in one place rather than spread across ad hoc scripts.

### ingress-nginx

ingress-nginx was used because it gives the lab a concrete ingress controller to validate, and the current configuration is explicitly ingress-nginx.

### Safe drain behavior

The drain drill avoids the Redis PVC node because local-path storage is node-bound. Draining that node would make the storage tradeoff dominate the demonstration.

### At-least-once behavior

The worker path is intentionally at-least-once. Jobs can be retried, and retry state is visible. That is appropriate for a lab whose purpose is to show failure handling rather than perfect exactly-once semantics.

### Retry and dead-letter handling

Retries and dead-lettering exist so the lab can demonstrate operational judgment around transient failure, persistence of failure state, and a bounded retry budget.

### Idempotency and backpressure

The API supports idempotency to prevent duplicate event creation under retry, and queue-depth backpressure to keep the queue from growing without bound.

## Limitations

- One physical Proxmox host
- No Redis Sentinel, Cluster, or HA
- Redis local-path storage is node-bound
- A job can remain stranded in `events:processing` if a worker dies after reservation
- Production recovery would require lease-backed ownership or a queue with pending-entry recovery
- Prometheus scraping worker metrics through one Service may not provide complete per-pod metrics after horizontal scaling
- This is a local lab rather than a remote multi-host deployment
- Operational scripts and drills are not a substitute for comprehensive source-level automated test coverage

## What I Would Change for Production

- Move Redis to a managed or replicated HA service
- Replace local-path storage with storage that survives node loss and supports recovery testing
- Add stronger source-level automated tests and production-style observability alerts
- Rework worker ownership so reserved jobs recover cleanly after pod death
