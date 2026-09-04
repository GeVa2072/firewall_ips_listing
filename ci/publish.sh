#!/usr/bin/env bash
set -euo pipefail

# Publish target/*.json to the 'public' branch (raw URL = stable latest,
# publicly downloadable) and ensure a 'latest' release links them.
#
# Required CI/CD variable:
#   PROJECT_TOKEN  Project Access Token with `api` + `write_repository` scope
#
# The 'public' branch must allow force-push (do not protect it, or allow
# force-push in its protection rule).

: "${PROJECT_TOKEN:?PROJECT_TOKEN CI variable is required (api + write_repository scope)}"
: "${CI_PROJECT_ID:?}"
: "${CI_PROJECT_URL:?}"
: "${CI_API_V4_URL:?}"
: "${CI_DEFAULT_BRANCH:=main}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$SCRIPT_DIR/target"
PUBLISH_BRANCH="public"
AUTH_URL="${CI_PROJECT_URL/#https:\/\//https://oauth2:${PROJECT_TOKEN}@}"
API="$CI_API_V4_URL/projects/$CI_PROJECT_ID"

if [ ! -d "$TARGET" ] || [ -z "$(ls -A "$TARGET"/*.json 2>/dev/null)" ]; then
  echo "Error: no JSON in target/. Run grab_ip.sh first." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. Push JSON snapshots to the 'public' branch (orphan, force-push).
#    Raw URL serves the latest content: a stable, public "latest" download.
# ---------------------------------------------------------------------------
echo ">>> Publishing JSON to branch ${PUBLISH_BRANCH}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if git clone --depth 1 --branch "$PUBLISH_BRANCH" "${AUTH_URL}" "$TMP" 2>/dev/null; then
  : # branch exists
else
  git clone --depth 1 "${AUTH_URL}" "$TMP"
  git -C "$TMP" checkout --orphan "$PUBLISH_BRANCH"
  git -C "$TMP" rm -rf . 2>/dev/null || true
fi

mkdir -p "$TMP/target"
cp "$TARGET"/*.json "$TMP/target/"

git -C "$TMP" config user.email "ci@gitlab.vanelsuve.fr"
git -C "$TMP" config user.name "CI bot"
git -C "$TMP" add -A
git -C "$TMP" commit -m "chore: refresh IP snapshots ($(date -u +%FT%TZ))" || {
  echo "No changes since last run."
}
git -C "$TMP" push --force origin "$PUBLISH_BRANCH"

# ---------------------------------------------------------------------------
# 2. Ensure tag 'latest' and release 'latest' exist, linking the raw URLs.
#    Idempotent: created once, links are stable (raw URL always serves latest).
# ---------------------------------------------------------------------------
echo ">>> Ensuring release 'latest'"
if ! curl -sf --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" "${API}/repository/tags/latest" >/dev/null 2>&1; then
  curl -sf --request POST --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
    --data-urlencode "tag_name=latest" \
    --data-urlencode "ref=${CI_DEFAULT_BRANCH}" \
    "${API}/repository/tags" >/dev/null
fi

DESC="IP snapshots auto-refreshed hourly. Files always serve the latest content via the \`public\` branch raw URLs below."

# Try to create the release; if it already exists (409), update the description.
if ! curl -sf --request POST --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
     --header "Content-Type: application/json" \
     --data "{\"name\":\"Latest IP snapshots\",\"tag_name\":\"latest\",\"description\":\"${DESC}\"}" \
     "${API}/releases" >/dev/null 2>&1; then
  curl -sf --request PUT --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
    --data-urlencode "description=${DESC}" \
    "${API}/releases/latest" >/dev/null
fi

# Add release links to each JSON raw URL (idempotent: skip existing).
for f in "$TARGET"/*.json; do
  name=$(basename "$f" .json)
  url="${CI_PROJECT_URL}/-/raw/${PUBLISH_BRANCH}/target/${name}.json"
  link_name="${name}.json"
  # Check if link already exists
  if curl -sf --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" "${API}/releases/latest/assets/links" \
     | jq -e --arg n "$link_name" '.[] | select(.name==$n)' >/dev/null 2>&1; then
    continue
  fi
  curl -sf --request POST --header "PRIVATE-TOKEN: ${PROJECT_TOKEN}" \
    --data-urlencode "name=${link_name}" \
    --data-urlencode "url=${url}" \
    --data-urlencode "link_type=other" \
    "${API}/releases/latest/assets/links" >/dev/null
done

echo ">>> Done. Public download URLs:"
for f in "$TARGET"/*.json; do
  name=$(basename "$f")
  echo "    ${CI_PROJECT_URL}/-/raw/${PUBLISH_BRANCH}/target/${name}"
done
echo ">>> Release page: ${CI_PROJECT_URL}/-/releases/latest"
