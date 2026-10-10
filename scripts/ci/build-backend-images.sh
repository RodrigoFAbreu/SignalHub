#!/usr/bin/env bash
# Builds the backend image once for this machine's platform and tags it twice, the
# two ways CI starts a stack (docs/development.md#ci):
#
#   signalhub-backend:check   as the release builds it, with the test version
#                             0.0.0-ci (scripts/release/build-image.sh)
#   signalhub-backend:local   as `docker compose up --build` builds it, a
#                             development build with no version
#
# Both come from the same Dockerfile and BuildKit builder, so the second build
# reuses every layer of the first: only the labels differ. With an argument, the
# images are also saved to that file (gzip), for the jobs that start a stack.
#
#   scripts/ci/build-backend-images.sh [FILE]
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
revision=$(git -C "$root" rev-parse HEAD)
platform=linux/$(docker version --format '{{.Server.Arch}}')

"$root/scripts/release/build-image.sh" 0.0.0-ci "$revision" load
# Compose builds ./backend with no build arguments; so does this.
docker buildx build --builder signalhub-release --platform "$platform" \
  --provenance=false --sbom=false --tag signalhub-backend:local --load "$root/backend" >&2

if [ $# -ge 1 ]; then
  docker save signalhub-backend:check signalhub-backend:local | gzip --fast > "$1"
fi
