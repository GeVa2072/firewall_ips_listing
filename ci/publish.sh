#!/usr/bin/env bash
set -euo pipefail

# Publish target/*.json as downloadable release assets.
#
# Storage:  Generic Package Registry, package "firewall_ips", version "latest"
#           (overwritten each run, no accumulation, stable URL).
# Release:  tag "latest" with asset links using direct_asset_path, so files are
#           downloadable at the permanent URL:
#             <project>/-/releases/latest/downloads/<name>.json
#
# Required CI/CD variable:
#   PROJECT_TOKEN  Project Access Token with `api` scope, used only for tag
#                  and release creation. Package uploads use $CI_JOB_TOKEN
#                  (automatically provided by GitLab CI).

: "${PROJECT_TOKEN:?PROJECT_TOKEN CI variable is required (api scope)}"
: "${CI_PROJECT_ID:?}"
: "${CI_PROJECT_URL:?}"
: "${CI_API_V4_URL:?}"
: "${CI_DEFAULT_BRANCH:=main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$SCRIPT_DIR/target"
PKG_NAME="firewall_ips"
PKG_VERSION="latest"
TAG="latest"
API="$CI_API_V4_URL/projects/$CI_PROJECT_ID"

if [ ! -d "$TARGET" ] || [ -z "$(ls -A "$TARGET"/*.json 2>/dev/null)" ]; then
  echo "Error: no JSON in target/. Run grab_ip.sh first." >&2
  exit 1
fi

# curl wrapper that fails loudly: prints HTTP status + body on error.
curl_api() {
  local out code
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
# 1. Upload each JSON to the Generic Package Registry (version "latest").
#    Overwrites the previous version; no accumulation.
# ---------------------------------------------------------------------------
echo ">>> Uploading JSON to package registry (${PKG_NAME}/${PKG_VERSION})"
for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  enc=$(printf '%s' "$name" | sed 's/ /%20/g')
  curl_api --request PUT \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
    --upload-file "$f" \
    "${API}/packages/generic/${PKG_NAME}/${PKG_VERSION}/${enc}" >/dev/null
  echo "    uploaded ${name}"
done

# ---------------------------------------------------------------------------
# 2. Ensure tag "latest" exists (release needs a tag).
# ---------------------------------------------------------------------------
echo ">>> Ensuring tag '${TAG}'"
if ! curl_api --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" "${API}/repository/tags/${TAG}" >/dev/null 2>&1; then
  curl_api --request POST --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
    --data-urlencode "tag_name=${TAG}" \
    --data-urlencode "ref=${CI_DEFAULT_BRANCH}" \
    "${API}/repository/tags" >/dev/null
fi

# ---------------------------------------------------------------------------
# 3. Ensure release "latest" exists.
# ---------------------------------------------------------------------------
echo ">>> Ensuring release '${TAG}'"
DESC="IP snapshots auto-refreshed hourly. Files always serve the latest content."
if ! curl_api --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" "${API}/releases/${TAG}" >/dev/null 2>&1; then
  curl_api --request POST --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "{\"name\":\"Latest IP snapshots\",\"tag_name\":\"${TAG}\",\"description\":\"${DESC}\"}" \
    "${API}/releases" >/dev/null
else
  curl_api --request PUT --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
    --data-urlencode "description=${DESC}" \
    "${API}/releases/${TAG}" >/dev/null
fi

# ---------------------------------------------------------------------------
# 4. Sync asset links: delete existing with same name, re-create fresh.
#    Each link points to the package registry download URL with a
#    direct_asset_path so the permanent downloads/ URL works.
# ---------------------------------------------------------------------------
echo ">>> Syncing asset links"
existing=$(curl_api --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" "${API}/releases/${TAG}/assets/links")

for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  pkg_url="${API}/packages/generic/${PKG_NAME}/${PKG_VERSION}/$(printf '%s' "$name" | sed 's/ /%20/g')"
  asset_path="/${name}"

  link_id=$(printf '%s' "$existing" | jq -r --arg n "$name" '.[] | select(.name==$n) | .id')
  if [ -n "$link_id" ] && [ "$link_id" != "null" ]; then
    curl_api --request DELETE --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
      "${API}/releases/${TAG}/assets/links/${link_id}" >/dev/null
  fi

  curl_api --request POST --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
    --data-urlencode "name=${name}" \
    --data-urlencode "url=${pkg_url}" \
    --data-urlencode "direct_asset_path=${asset_path}" \
    --data-urlencode "link_type=other" \
    "${API}/releases/${TAG}/assets/links" >/dev/null
  echo "    linked ${name} -> ${CI_PROJECT_URL}/-/releases/${TAG}/downloads/${name}"
done

echo ">>> Done. Public download URLs:"
for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  echo "    ${CI_PROJECT_URL}/-/releases/${TAG}/downloads/${name}"
done
echo ">>> Release page: ${CI_PROJECT_URL}/-/releases/${TAG}"
