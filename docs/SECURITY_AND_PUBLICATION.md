# Security and Publication

This repository is published from an allowlist-based staging copy. The staging tree is assembled from selected source files only; it is not a sanitized checkout of the live repositories.

## Excluded Content

The publication copy excludes:

- Terraform state and state backups
- `terraform.tfvars`
- kubeconfig files
- SSH private keys and SSH authentication material
- credentials and tokens
- generated secrets
- container image archives
- logs
- caches
- backups
- temporary files
- Git metadata and Git history

## Why `.gitignore` Is Not Enough

`.gitignore` only affects untracked files. It does not prove that tracked files are safe, nor does it prevent accidental inclusion of sensitive content already present in source directories. Publication therefore uses an allowlist copy, a manifest, and a verification script.

## Verification

The publication process checks:

- prohibited filenames and directories
- obvious secret patterns without printing secret values
- manifest-to-tree consistency
- presence of the expected public files

`tools/verify-public-copy.sh` implements those checks for the staged repository.

## Topology Examples

RFC1918 addresses and other lab topology details may appear in the public copy as non-secret examples of the local environment. They are operational context, not credentials.

## Publication Boundary

This repository must not be treated as containing deployable production credentials or a ready-to-run production environment. It is a publication-safe description of a local lab and its supporting automation.
