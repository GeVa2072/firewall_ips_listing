# CI image with all runtime tools pre-installed.
# GitLab CI checks out the repo on top of this image, so we only
# need the tools — not the project files.
#
# Pinned to alpine:3.21 for reproducibility (not :latest).
FROM alpine:3.21

RUN apk add --no-cache bash bind-tools jq curl coreutils
