# Agent Instructions

## Purpose

This repository is a publication staging copy of a self-directed platform lab. Keep changes factual, narrow, and safe for public release.

## Repository Layout

- `app/`: Go API and worker services
- `k8s/`: Kubernetes manifests
- `observability/`: Grafana and Prometheus configuration
- `infra/proxmox-lab/`: Terraform, Proxmox automation, and operator tooling
- `docs/`: publication-facing documentation
- `tools/`: audit and verification helpers

## Working Rules

- Inspect the current file contents before making claims about behavior.
- Do not add secrets, credentials, state files, caches, binaries, logs, backups, or temporary files.
- Keep documentation aligned with observed implementation.
- Preserve the public copy as a separate tree; do not edit any source repository in place when preparing publication artifacts.
- Avoid publishing host-specific paths or environment-specific instructions.

## Validation

- Run `bash -n` on all shell scripts you add or copy.
- Run `go test ./...` and `go build ./...` from the repository root for Go changes.
- Run `terraform fmt -check` on staged Terraform source.
- Run `terraform validate` only when it can succeed without credentials or state.
- Run `jq` over staged JSON files.
- Run the public-copy verification script before release.

## Publication Rules

- Publish only allowlisted source files and documentation.
- Exclude generated state, hidden tool caches, private keys, tokens, credentials, and other sensitive artifacts.
- Keep the manifest synchronized with the staged file tree.
