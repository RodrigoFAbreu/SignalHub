#!/usr/bin/env bash
# Builds the backend image for this machine's platform the way a release does
# (docs/development.md#release-process), with the version and commit baked in.
#
#   scripts/release/build-image.sh VERSION REVISION load
#     loads it into the local Docker as signalhub-backend:check (CI)
#   scripts/release/build-image.sh VERSION REVISION push
#     pushes it to GHCR by digest, untagged, with BuildKit's provenance and SBOM
#     attestations, and prints the digest (the release, which then joins both
#     platforms under one tag)
#
# VERSION is without "v" (1.2.3); REVISION is the full commit hash, which must be
# checked out, since its time is the image's creation time.
set -euo pipefail

if [ $# -ne 3 ] || { [ "$3" != load ] && [ "$3" != push ]; }; then
  echo "usage: $0 VERSION REVISION load|push" >&2
  exit 2
fi
version=$1 revision=$2 mode=$3
repository=ghcr.io/rodrigofabreu/signalhub
root=$(cd "$(dirname "$0")/../.." && pwd)
# The commit's time rather than the clock's, so both platforms carry the same one.
created=$(git -C "$root" show --no-patch --format=%cI "$revision")
platform=linux/$(docker version --format '{{.Server.Arch}}')

# Pushing by digest needs BuildKit in a container rather than the Docker daemon's own.
docker buildx inspect signalhub-release > /dev/null 2>&1 ||
  docker buildx create --name signalhub-release --driver docker-container > /dev/null

args=(
  --builder signalhub-release
  --platform "$platform"
  --build-arg "SIGNALHUB_VERSION=$version"
  --build-arg "SIGNALHUB_REVISION=$revision"
  --build-arg "SIGNALHUB_CREATED=$created"
)
if [ "$mode" = load ]; then
  # The local image store takes no attestations; everything else is as released.
  docker buildx build "${args[@]}" --provenance=false --sbom=false \
    --tag signalhub-backend:check --load "$root/backend" >&2
else
  metadata=$(mktemp)
  trap 'rm -f "$metadata"' EXIT
  docker buildx build "${args[@]}" --provenance=mode=max --sbom=true \
    --output "type=image,name=$repository,push-by-digest=true,name-canonical=true,push=true" \
    --metadata-file "$metadata" "$root/backend" >&2
  jq --raw-output '."containerimage.digest"' "$metadata"
fi
