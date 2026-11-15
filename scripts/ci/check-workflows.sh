#!/usr/bin/env bash
# Keep workflow validation available after a primary Python-check failure.
set -euo pipefail

docker build --quiet --tag actionlint .github/tools/actionlint
# actionlint 1.7.12 predates GitHub concurrency.queue. Ignore only that field
# diagnostic until the next linter release supports it. Keep all other checks.
docker run --rm --volume "$PWD:/repo" --workdir /repo actionlint -color \
  -ignore '^unexpected key "queue" for "concurrency" section\.' \
  .github/workflows/*.yml examples/github-actions/*.yml
