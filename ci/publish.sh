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

# Stash freshly generated JSON outside the repo so git operations cannot
# clobber them (target/ is gitignored and the public branch may track them).
STASH=$(mktemp -d)
cp "$TARGET"/*.json "$STASH"/

git remote set-url origin "${AUTH_URL}"
if git fetch --depth 1 origin "$PUBLISH_BRANCH" 2>/dev/null; then
  git checkout -B "$PUBLISH_BRANCH" FETCH_HEAD
else
  git checkout --orphan "$PUBLISH_BRANCH"
fi
git rm -rf --quiet . 2>/dev/null || true

mkdir -p "$TARGET"
cp "$STASH"/*.json "$TARGET"/
rm -rf "$STASH"

git config user.email "ci@gitlab.vanelsuve.fr"
git config user.name "CI bot"
git add -f "$TARGET"/*.json
git commit -q -m "chore: refresh IP snapshots ($(date -u +%FT%TZ))" || {
  echo "No changes since last run."
}
git push --force origin "$PUBLISH_BRANCH"
# Back to the default branch so subsequent steps (if any) are not surprised.
git checkout -q "$CI_DEFAULT_BRANCH"

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
