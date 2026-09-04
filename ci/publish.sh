#!/usr/bin/env bash
set -euo pipefail

# Publish target/*.json to the Generic Package Registry.
#
# Each run deletes the old package version (to avoid file accumulation),
# then uploads fresh JSON. The download URL is stable, public (if the
# project is public), and always serves the latest content:
#   <gitlab>/api/v4/projects/<id>/packages/generic/firewall_ips/latest/<name>.json
#
# Uses only $CI_JOB_TOKEN (automatically provided by GitLab CI, no PAT).

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

# ---------------------------------------------------------------------------
# 1. Delete the old package version to avoid file accumulation.
#    The generic registry adds files on each PUT instead of overwriting,
#    so we wipe the version before uploading fresh files.
# ---------------------------------------------------------------------------
echo ">>> Cleaning up old package (${PKG_NAME}/${PKG_VERSION})"
pkg_id=$(curl_api \
  --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
  "${API}/packages?package_type=generic&package_name=${PKG_NAME}&package_version=${PKG_VERSION}" \
  | jq -r '.[0].id // empty')
if [ -n "$pkg_id" ] && [ "$pkg_id" != "null" ]; then
  curl_api --request DELETE \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    "${API}/packages/${pkg_id}" >/dev/null
  echo "    deleted old package (id=${pkg_id})"
else
  echo "    no old package to delete"
fi

# ---------------------------------------------------------------------------
# 2. Upload each JSON to the Generic Package Registry.
# ---------------------------------------------------------------------------
echo ">>> Uploading JSON to package registry (${PKG_NAME}/${PKG_VERSION})"
for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  curl_api --request PUT \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    --upload-file "$f" \
    "${API}/packages/generic/${PKG_NAME}/${PKG_VERSION}/${name}" >/dev/null
  echo "    uploaded ${name}"
done

echo ">>> Done. Download URLs (public if project is public):"
for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  echo "    ${API}/packages/generic/${PKG_NAME}/${PKG_VERSION}/${name}"
done
