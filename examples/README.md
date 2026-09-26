# Integration examples

Small producers that publish useful notifications to SignalHub. Each one
uses only the public HTTP API (`POST /api/v1/events`, see
[docs/architecture.md](../docs/architecture.md#events)), directly or through
the [Python package and command](../sdk/python/README.md). SignalHub treats
their events like any other: no example needs, or gets, anything special in
the backend or the app. They are starting points to copy and adapt, not
supported products.

| Example | Producer | Publishes | Uses |
|---|---|---|---|
| [`shell/run-and-notify.sh`](shell/run-and-notify.sh) | any command, a cron job or script step | `COMPLETED`/`NORMAL` when the command succeeds, `BLOCKED`/`HIGH` when it fails | `sh`, `curl`, `jq` |
| [`disk-usage/check-disk-usage.sh`](disk-usage/check-disk-usage.sh) | a homelab disk monitor | `ACTION_REQUIRED`/`HIGH` when a file system is fuller than a threshold, `CRITICAL` from 98% | `sh`, the `signalhub` command |
| [`github-actions/notify-on-failure.yml`](github-actions/notify-on-failure.yml) | GitHub Actions | `BLOCKED`/`HIGH` when a workflow run fails | a workflow, `curl`, `jq` |
| [`coding-agent/agent_hook.py`](coding-agent/agent_hook.py) | a coding agent (Claude Code hooks) | `ACTION_REQUIRED`/`HIGH` when the agent waits for the owner, `COMPLETED`/`NORMAL` when it finishes | the Python package |
| [`usage-threshold/usage_threshold.py`](usage-threshold/usage_threshold.py) | a quota, budget or data-plan meter | `ACTION_REQUIRED`/`HIGH` at a warning level, `BLOCKED`/`CRITICAL` at the limit, once each | the Python package |

Each example maps its own states onto the generic `category` and
`severity`, names what it is about in `context` (a host, repository or
project), and puts its own details in `metadata`, which SignalHub stores and
shows but never interprets.

## Setup

Give each producer its own API key, so it shows under its own name and can
be revoked on its own. With the management API (see the
[repository README](../README.md)):

```sh
curl -s http://localhost:8080/api/v1/admin/producers \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "disk-monitor"}' | jq -r .apiKey
```

Every example reads the same settings from the environment:

| Setting | Meaning |
|---|---|
| `SIGNALHUB_URL` | The server's base address, e.g. `https://signalhub.example` |
| `SIGNALHUB_API_KEY` | The producer's API key (`shpk1_...`) |
| `SIGNALHUB_API_KEY_FILE` | A file holding the key, instead of `SIGNALHUB_API_KEY` (Python examples and the `signalhub` command) |

Keep the key in a file readable only by the producer's user, or in the CI
system's secret store; never in the script or a repository. The Python
examples and the disk monitor need the package, attached to every release
as a wheel (see [sdk/python/README.md](../sdk/python/README.md#install)).

Only the GitHub Actions example retries (`curl --retry`), and it sends an
`Idempotency-Key` naming the run and its attempt, so a retry after a timeout
never stores the event twice (see
[docs/architecture.md](../docs/architecture.md#idempotent-publishing)). The
others publish once per run and report a failure; a producer that adds
retries should send such a key too.

## Shell: run a command and report its outcome

```sh
examples/shell/run-and-notify.sh "Nightly backup" restic backup /srv
```

It runs the command, publishes whether it succeeded, with its exit status
and duration in the metadata, and exits with the command's status. A failed
publish is reported on standard error but does not change the exit status.
In a crontab:

```
SIGNALHUB_URL=https://signalhub.example
0 3 * * * . "$HOME/.signalhub-key" && /opt/signalhub/run-and-notify.sh "Nightly backup" /usr/local/bin/backup
```

where `~/.signalhub-key` holds `export SIGNALHUB_API_KEY=shpk1_...`.

## Homelab: disk usage

```sh
examples/disk-usage/check-disk-usage.sh /srv 90
```

It publishes when the file system holding `/srv` is at least 90% full, with
the mount point, the percentage and the space left, and exits with the
`signalhub` command's status; below the threshold it does nothing. Every run
over the threshold publishes again, so run it hourly or daily, for example
from a systemd timer or cron:

```
SIGNALHUB_URL=https://signalhub.example
SIGNALHUB_API_KEY_FILE=/etc/signalhub/disk-monitor.key
0 * * * * /opt/signalhub/check-disk-usage.sh / 90
```

## GitHub Actions: a failed workflow run

Copy [`notify-on-failure.yml`](github-actions/notify-on-failure.yml) to
`.github/workflows/` in the repository to watch, and list the workflows to
watch under `workflows:`. In the repository settings, add a variable
`SIGNALHUB_URL` and a secret `SIGNALHUB_API_KEY`. When a listed workflow
fails, it publishes the workflow, branch, commit and a link to the run, with
the repository as the context, once per run attempt however often `curl`
retries. The server must be reachable from GitHub's
runners (see [docs/deployment.md](../docs/deployment.md)); on a self-hosted
runner it can be a private address.

To notify from inside a job instead, for example after a deployment, run the
same `curl` command, or `pip install` the package and use
`signalhub send`, as the job's last step.

## Coding agent: human gates and completions

[`agent_hook.py`](coding-agent/agent_hook.py) is a
[Claude Code hook](https://code.claude.com/docs/en/hooks). It
publishes an `ACTION_REQUIRED` event with the agent's message when the agent
waits for the owner (a permission request, or idle waiting for input) and a
`COMPLETED` event when it finishes, with the project directory's name as the
context and the session ID in the metadata. In `~/.claude/settings.json` (or
a project's `.claude/settings.json`):

```json
{
  "hooks": {
    "Notification": [
      {"hooks": [{"type": "command", "command": "python3 /opt/signalhub/agent_hook.py"}]}
    ],
    "Stop": [
      {"hooks": [{"type": "command", "command": "python3 /opt/signalhub/agent_hook.py"}]}
    ]
  }
}
```

with `SIGNALHUB_URL` and `SIGNALHUB_API_KEY_FILE` in the environment the
agent runs in. The hook always exits `0`: an unreachable SignalHub is
reported on standard error and never blocks or changes the agent's work.
Another agent or orchestrator can pipe the same JSON to it
(`hook_event_name`, `message`, `cwd`, `session_id`), or publish with
`signalhub send --category ACTION_REQUIRED ...` at its own human gates.

## Usage threshold: quotas and budgets

```sh
examples/usage-threshold/usage_threshold.py --name "API quota" \
  --used "$(get-usage)" --limit 10000 --warn-at 80 \
  --context my-account --state-file ~/.cache/signalhub/api-quota.level
```

It publishes once when usage reaches 80% of the limit and once more at the
limit. The state file remembers the last level notified, so it can run every
few minutes; when usage drops below the warning level again (a new billing
period), the next crossing notifies again. The state file is only updated
after a successful publish, so a failed one is tried again on the next run.
Exit statuses follow the `signalhub` command: `1` rejected, `2` usage or
configuration error, `3` temporary failure.

## Tests

From the repository root, with the package installed
(`pip install ./sdk/python`):

```sh
shellcheck examples/*/*.sh
python -m unittest discover --start-directory examples/tests --verbose
```

The tests run every example, including the GitHub Actions step's script,
against an in-process fake of the events endpoint on `127.0.0.1`, with no
network or credentials. CI also runs them, lints the example workflow with
actionlint, and runs the examples against the real backend in the Compose
smoke test, each as its own producer.
