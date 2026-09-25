#!/bin/sh
# Runs a command and publishes its outcome to SignalHub, with plain HTTP
# (curl and jq, no SDK). The command's exit status is kept, so it can wrap a
# cron job or a script step without changing what the caller sees.
#
# Usage: run-and-notify.sh TITLE COMMAND [ARGUMENT...]
# Needs SIGNALHUB_URL and SIGNALHUB_API_KEY in the environment.
set -u

if [ "$#" -lt 2 ]; then
  echo "usage: run-and-notify.sh TITLE COMMAND [ARGUMENT...]" >&2
  exit 2
fi
: "${SIGNALHUB_URL:?SIGNALHUB_URL is not set}"
: "${SIGNALHUB_API_KEY:?SIGNALHUB_API_KEY is not set}"

title=$1
shift
started=$(date +%s)
"$@"
status=$?
seconds=$(($(date +%s) - started))

if [ "$status" -eq 0 ]; then
  category=COMPLETED severity=NORMAL outcome=succeeded
else
  category=BLOCKED severity=HIGH outcome="failed with exit status $status"
fi

# jq builds the JSON, so titles and commands with quotes stay valid.
event=$(jq --null-input \
  --arg category "$category" --arg severity "$severity" \
  --arg title "$title $outcome" --arg outcome "$outcome" --arg command "$*" \
  --arg context "$(uname -n)" \
  --argjson status "$status" --argjson seconds "$seconds" \
  '{category: $category, severity: $severity, title: $title[:200],
    message: "`\($command)` \($outcome) after \($seconds) s."[:4000],
    context: $context,
    metadata: {command: $command, exitStatus: $status, durationSeconds: $seconds}}')

# The key is passed on standard input, so it never shows in process lists.
if ! response=$(printf 'Authorization: Bearer %s\n' "$SIGNALHUB_API_KEY" |
  curl --fail-with-body --silent --show-error --max-time 10 \
    --header @- --header 'Content-Type: application/json' \
    --data "$event" "$SIGNALHUB_URL/api/v1/events"); then
  echo "run-and-notify.sh: could not publish to SignalHub: $response" >&2
fi
exit "$status"
