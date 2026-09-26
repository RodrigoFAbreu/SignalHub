#!/usr/bin/env bash
# Checks a backend image the way a release checks the one it published
# (docs/development.md#release-process): its labels and architecture, then,
# started with a throwaway PostgreSQL, the version and commit it reports at
# /q/info and in its startup summary.
#
#   scripts/release/check-image.sh IMAGE VERSION [REVISION]
#
# VERSION is the release without "v" (1.2.3), or "development" for a build the
# release did not make; REVISION is the commit the image must name, omitted when
# it names none.
set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  echo "usage: $0 IMAGE VERSION [REVISION]" >&2
  exit 2
fi
image=$1 version=$2 revision=${3:-}
root=$(cd "$(dirname "$0")/../.." && pwd)
postgres_image=$(sed -n 's/^ *image: \(postgres:.*\)$/\1/p' "$root/compose.yaml")
name=signalhub-check-$$

expect() { # what, actual, expected
  if [ "$2" != "$3" ]; then
    echo "$1: expected '$3', got '$2'" >&2
    exit 1
  fi
  echo "$1: ${2:-(none)}"
}
label() {
  docker image inspect --format "{{ index .Config.Labels \"$1\" }}" "$image"
}

expect "version label" "$(label org.opencontainers.image.version)" "$version"
expect "revision label" "$(label org.opencontainers.image.revision)" "$revision"
expect "source label" "$(label org.opencontainers.image.source)" https://github.com/RodrigoFAbreu/SignalHub
echo "created label: $(label org.opencontainers.image.created)"
expect "architecture" "$(docker image inspect --format '{{.Architecture}}' "$image")" \
  "$(docker version --format '{{.Server.Arch}}')"

cleanup() {
  docker rm --force "$name-backend" "$name-postgres" > /dev/null 2>&1 || true
  docker network rm "$name" > /dev/null 2>&1 || true
}
trap cleanup EXIT
docker network create "$name" > /dev/null
docker run --detach --name "$name-postgres" --network "$name" \
  --env POSTGRES_DB=signalhub --env POSTGRES_USER=signalhub --env POSTGRES_PASSWORD=check \
  "$postgres_image" > /dev/null
# Over TCP: while the image initializes the database, it listens only on its socket.
for _ in $(seq 60); do
  docker exec "$name-postgres" pg_isready --quiet --host 127.0.0.1 --username signalhub && break
  sleep 1
done
docker run --detach --name "$name-backend" --network "$name" --publish 127.0.0.1::8080 \
  --env "SIGNALHUB_DB_URL=jdbc:postgresql://$name-postgres:5432/signalhub" \
  --env SIGNALHUB_DB_USERNAME=signalhub --env SIGNALHUB_DB_PASSWORD=check \
  "$image" > /dev/null
status=starting
for _ in $(seq 90); do
  status=$(docker inspect --format '{{.State.Health.Status}}' "$name-backend")
  [ "$status" = healthy ] && break
  [ "$(docker inspect --format '{{.State.Running}}' "$name-backend")" = true ] || break
  sleep 2
done
if [ "$status" != healthy ]; then
  docker logs "$name-backend" >&2
  echo "the backend did not become healthy ($status)" >&2
  exit 1
fi

info=$(curl --fail --silent --show-error "http://$(docker port "$name-backend" 8080/tcp | head -n 1)/q/info")
expect "version at /q/info" "$(jq --raw-output '.signalhub.version' <<< "$info")" "$version"
expect "revision at /q/info" "$(jq --raw-output '.signalhub.revision // ""' <<< "$info")" "$revision"

if [ "$version" = development ]; then
  release="SignalHub development build"
else
  release="SignalHub $version"
fi
[ -z "$revision" ] || release="$release (commit $revision)"
if ! docker logs "$name-backend" 2>&1 | grep --quiet --fixed-strings "$release; Configuration: profile prod;"; then
  docker logs "$name-backend" >&2
  echo "the startup summary does not begin with '$release'" >&2
  exit 1
fi
echo "startup summary: begins with '$release'"
