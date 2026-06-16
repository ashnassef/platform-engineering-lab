#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "verify-public-copy: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -e "$path" ]] || fail "missing required file: $path"
}

echo "Checking for prohibited paths..."
prohibited_paths=(
  ".git"
  ".terraform"
  ".platform"
  "terraform.tfstate"
  "terraform.tfstate.backup"
  "terraform.tfvars"
)

for path in "${prohibited_paths[@]}"; do
  if find . \
    -path './.git' -prune -o \
    \( -path "./$path" -o -path "./$path/*" \) -print \
    | grep -q .; then
    fail "prohibited path present: $path"
  fi
done

for pattern in \
  '*.pem' '*.key' '*.crt' '*.p12' '*.pfx' \
  'id_rsa' 'id_rsa.*' 'id_ed25519' 'id_ed25519.*' \
  '*.kubeconfig' 'kubeconfig*' '*.tfstate' '*.tfstate.*' '*.tfvars' '*.log' '*.bak' '*.orig' '*.rej' '*.tmp'
do
  if find . -type f -name "$pattern" | grep -q .; then
    fail "prohibited filename present for pattern: $pattern"
  fi
done

echo "Scanning for obvious secrets..."
secret_regex='-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----|^[[:space:]]*(password|passwd|token|secret|client_secret|api_key)[[:space:]]*[:=][[:space:]]*[^"$]{8,}[[:space:]]*$|ssh-rsa [A-Za-z0-9+/=]{100,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'

set +e
secret_scan_output="$(
  grep -RInI --binary-files=without-match -E \
    --exclude-dir=.git \
    --exclude-dir=.terraform \
    --exclude-dir=.platform \
    --exclude=PUBLICATION_MANIFEST.txt \
    -e "$secret_regex" . 2>/dev/null
)"
secret_scan_status=$?
set -e

if ((secret_scan_status > 1)); then
  fail "secret scan failed"
fi

secret_hits=()
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  secret_hits+=("$match")
done <<<"$secret_scan_output"

if ((${#secret_hits[@]} > 0)); then
  echo "verify-public-copy: secret-like content found in:" >&2
  printf '%s\n' "${secret_hits[@]}" | cut -d: -f1 | sort -u >&2
  exit 1
fi

require_file PUBLICATION_MANIFEST.txt

echo "Validating manifest..."
tmp_manifest="$(mktemp)"
trap 'rm -f "$tmp_manifest"' EXIT
find . -type f \
  -not -path './.git/*' \
  -not -name 'PUBLICATION_MANIFEST.txt' \
  | sed 's#^\./##' | LC_ALL=C sort >"$tmp_manifest"
printf '%s\n' "PUBLICATION_MANIFEST.txt" >>"$tmp_manifest"
LC_ALL=C sort -o "$tmp_manifest" "$tmp_manifest"

if ! diff -u "$tmp_manifest" PUBLICATION_MANIFEST.txt >/dev/null; then
  diff -u "$tmp_manifest" PUBLICATION_MANIFEST.txt >&2 || true
  fail "manifest does not match the staged file tree"
fi

echo "Public copy verification passed."
