#!/usr/bin/env bash
# Run from backend/ before the shared Maven verification job.
set -euo pipefail

expected=$(sed -n 's/^ *image: \(postgres:[^@]*\)@.*/\1/p' ../compose.yaml)
test -n "$expected"
if grep -rnoE '(image-name=|")postgres:[^"[:space:]]*' src | grep -v -e ":image-name=$expected\$" -e ":\"$expected\$"; then
  echo "::error::These PostgreSQL images differ from compose.yaml's $expected"
  exit 1
fi
grep -q "image-name=$expected\$" src/main/resources/application.properties
