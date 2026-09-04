#!/usr/bin/env bash
set -euo pipefail

# Publish target/*.json to the Generic Package Registry.
#
# Files are uploaded with $CI_JOB_TOKEN (automatically provided by GitLab CI,
# no PAT needed) to package "firewall_ips", version "latest" (overwritten
# each run). The download URL is stable, public, and always serves the latest
# content:
#   <project>/-/packages/generic/firewall_ips/latest/<name>.json

: "${CI_JOB_TOKEN:?CI_JOB_TOKEN is required (provided automatically by GitLab CI)}"
: "${CI_PROJECT_ID:?}"
: "${CI_PROJECT_URL:?}"
: "${CI_API_V4_URL:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$SCRIPT_DIR/target"
PKG_NAME="firewall_ips"
PKG_VERSION="latest"
API="$CI_API_V4_URL/projects/$CI_PROJECT_ID"

if [ ! -d "$TARGET" ] || [ -z "$(ls -A "$TARGET"/*.json 2>/dev/null)" ]; then
  echo "Error: no JSON in target/. Run grab_ip.sh first." >&2
  exit 1
fi

# curl wrapper that fails loudly: prints HTTP status + body on error.
curl_api() {
  local out code body
  out=$(mktemp)
  curl -sS --write-out '%{http_code}' "$@" >"$out" 2>/dev/null
  code=$(tail -c3 "$out")
  body=$(head -c -3 "$out")
  rm -f "$out"
  if [ "$code" -ge 400 ]; then
    echo "HTTP ${code} on $*" >&2
    echo "$body" >&2
    return 22
  fi
  printf '%s' "$body"
}

echo ">>> Uploading JSON to package registry (${PKG_NAME}/${PKG_VERSION})"
for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  curl_api --request PUT \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    --upload-file "$f" \
    "${API}/packages/generic/${PKG_NAME}/${PKG_VERSION}/${name}" >/dev/null
  echo "    uploaded ${name}"
done

echo ">>> Done. Public download URLs:"
for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  echo "    ${CI_PROJECT_URL}/-/packages/generic/${PKG_NAME}/${PKG_VERSION}/${name}"
done
