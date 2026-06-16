# Production Readiness Notes

This is a lab readiness summary, not a production readiness claim.

## Lab capabilities demonstrated

- Infrastructure provisioning with Terraform
- Kubernetes workload scheduling
- Ingress-based service exposure
- Health and readiness checks
- Redis-backed queueing
- Redis PVC-backed persistence
- Redis AOF persistence
- API idempotency
- API queue backpressure
- Worker retry behavior
- Worker dead-letter behavior
- Prometheus metrics
- Grafana dashboard surface
- Operator status, smoke, drill, and diagnose commands

## Known limits

### Single physical host

The lab runs on one physical Proxmox host.

Limit:

- no physical host failover
- no physical failure-domain separation

Production direction:

- multiple physical hosts or cloud zones
- automated node replacement
- workload spreading
- tested failure-domain behavior

### k3s local-path storage

Redis uses k3s local-path storage.

Limit:

- the Redis volume is tied to the node that owns the local path volume
- Redis pod restart is covered
- full node loss is not covered

Production direction:

- managed Redis
- Redis Sentinel
- Redis Cluster
- replicated storage
- backup and restore validation

### Single Redis instance

Redis is deployed as one instance.

Limit:

- no Redis replica
- no automatic Redis failover
- no Redis cluster quorum

Production direction:

- HA Redis topology
- replication
- failover testing
- persistence monitoring
- backup verification

### Local image tarball deployment

Images are built locally and imported into k3s containerd.

Limit:

- no registry
- no artifact promotion workflow
- manual image artifact handling

Production direction:

- container registry
- immutable image tags
- image scanning
- signed artifacts
- CI build pipeline
- environment promotion

### ingress-nginx NodePort ingress

ingress-nginx uses a fixed NodePort.

Limit:

- no managed load balancer
- no DNS automation
- no TLS automation

Production direction:

- load balancer
- DNS
- TLS certificates
- ingress policy
- rate limiting where needed

### Basic observability

Prometheus and Grafana are present.

Limit:

- no alert rules
- no log aggregation
- no tracing
- no SLO definitions

Production direction:

- alerting
- SLOs
- logs
- traces
- incident runbooks
- dashboard ownership

### Minimal security hardening

The lab does not implement a full security model.

Limit:

- no network policies
- no external secret manager
- no RBAC hardening pass
- no image scanning

Production direction:

- least-privilege RBAC
- network policies
- secret management
- audit logs
- image vulnerability scanning
- TLS everywhere practical
