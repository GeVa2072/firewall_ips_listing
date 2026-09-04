#!/usr/bin/env bash
set -euo pipefail

# Download existing JSON from the Generic Package Registry into target/.
#
# This restores the last_seen history so grab_ip.sh can merge new resolutions
# with previous data instead of starting from scratch each run.
#
# Uses only $CI_JOB_TOKEN (automatically provided by GitLab CI, no PAT).

: "${CI_JOB_TOKEN:?CI_JOB_TOKEN is required (provided automatically by GitLab CI)}"
: "${CI_PROJECT_ID:?}"
: "${CI_API_V4_URL:?}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$SCRIPT_DIR/target"
DOMAIN_DIR="$SCRIPT_DIR/domains"
PKG_NAME="firewall_ips"
PKG_VERSION="latest"
API="$CI_API_V4_URL/projects/$CI_PROJECT_ID"

mkdir -p "$TARGET"

shopt -s nullglob

echo ">>> Fetching existing JSON from package registry (${PKG_NAME}/${PKG_VERSION})"
fetched=0
for file in "$DOMAIN_DIR"/*.txt; do
  name=$(basename "${file%.txt}")
  url="${API}/packages/generic/${PKG_NAME}/${PKG_VERSION}/${name}.json"
  code=$(curl -sS -o "$TARGET/${name}.json" -w '%{http_code}' \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    "$url" 2>/dev/null || true)
  if [ "$code" = "200" ]; then
    echo "    fetched ${name}.json"
    fetched=$((fetched + 1))
  else
    rm -f "$TARGET/${name}.json"
    echo "    ${name}.json: no existing data (HTTP ${code})"
  fi
done

echo ">>> Fetched ${fetched} file(s) from registry"
