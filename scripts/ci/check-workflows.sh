#!/usr/bin/env bash
# Keep workflow validation available after a primary Python-check failure.
set -euo pipefail

docker build --quiet --tag actionlint .github/tools/actionlint
docker run --rm --volume "$PWD:/repo" --workdir /repo actionlint -color \
  .github/workflows/*.yml examples/github-actions/*.yml
