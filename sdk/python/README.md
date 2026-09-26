# SignalHub for Python

A small producer package and command-line tool that publish events to
SignalHub. It uses only the public HTTP API (`POST /api/v1/events`, see
[docs/architecture.md](../../docs/architecture.md#events)) and only the
Python standard library. Python 3.10 or later.

Anything the package does can also be done with plain HTTP; see
[Without the SDK](#without-the-sdk).

## Install

The package is not on PyPI. Each SignalHub release attaches it, built with
that release's version: a wheel (`signalhub-X.Y.Z-py3-none-any.whl`), a
source archive (`signalhub-X.Y.Z.tar.gz`) and their checksums in
`SHA256SUMS`. Download the wheel, check it and install it:

```sh
version=1.2.3
curl --fail --location --remote-name-all \
  "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/signalhub-$version-py3-none-any.whl" \
  "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/SHA256SUMS"
sha256sum --check --ignore-missing SHA256SUMS
pip install "signalhub-$version-py3-none-any.whl"
# or, isolated, just for the command:
pipx install "signalhub-$version-py3-none-any.whl"
```

`signalhub --version` then prints the release, `SignalHub 1.2.3`, and so
does the package's metadata (`importlib.metadata.version("signalhub")`).
The SDK is part of SignalHub and has no version of its own; installing the
release your server runs is the simplest choice.

Releases up to v1.2.0 attach no SDK files; install those from the
repository at their tag, which also works for any later release:

```sh
pip install "signalhub @ git+https://github.com/RodrigoFAbreu/SignalHub@vX.Y.Z#subdirectory=sdk/python"
```

A package built from the repository, at a tag or from a checkout
(`pip install ./sdk/python`), was not built by a release: it has the
development placeholder version `0.0.0.dev0`, and `signalhub --version`
prints `SignalHub development build`. Prefer the release's wheel, which
names its release.

## Configure

A producer needs the server's base address and its API key, which the
operator issues through the management API (see the
[repository README](../../README.md)).

| Setting | Meaning |
|---|---|
| `SIGNALHUB_URL` | The server's base address, e.g. `https://signalhub.example` (with any path prefix of a reverse proxy). |
| `SIGNALHUB_API_KEY` | The producer's API key (`shpk1_...`). |
| `SIGNALHUB_API_KEY_FILE` | A file holding the API key, used when `SIGNALHUB_API_KEY` is unset. |

The command takes `--url` and `--api-key-file` too, but has no option for the
key itself, so the key never appears in process lists or shell history.
In CI, keep the key in the CI system's secret store and expose it as
`SIGNALHUB_API_KEY`.

## Command line

```sh
signalhub send \
  --category ACTION_REQUIRED \
  --severity HIGH \
  --title "Implementation review required" \
  --message "A human gate is waiting."
```

It prints the stored event's ID (`--json` prints the whole event).

| Option | Event field |
|---|---|
| `--category` (required) | `category`: `ACTION_REQUIRED`, `BLOCKED`, `COMPLETED` or `INFO` |
| `--severity` (required) | `severity`: `LOW`, `NORMAL`, `HIGH` or `CRITICAL` |
| `--title` (required) | `title`, at most 200 characters |
| `--message TEXT` | `message`, at most 4000 characters; `--message -` reads standard input |
| `--context NAME` | `context`, e.g. a repository, host or job |
| `--metadata JSON` | `metadata`, a JSON object |
| `--meta KEY=VALUE` | one metadata string value; repeatable, applied over `--metadata` |
| `--occurred-at TIMESTAMP` | `occurredAt`, ISO-8601 with an offset, e.g. `2026-09-25T14:03:00Z` |
| `--idempotency-key KEY` | not a field: the `Idempotency-Key` header, 1 to 200 visible ASCII characters (see below) |

Category and severity are case-insensitive, and `-` stands for `_`
(`--category action-required`). Values the command does not know are sent as
they are; the server decides.

Other options: `--url`, `--api-key-file PATH`, `--timeout SECONDS`
(default 10) and `--json`.

### Exit status

| Status | Meaning | Sending again |
|---|---|---|
| `0` | Published. | |
| `1` | Rejected: an invalid event (the violations are printed) or API key. | will not help |
| `2` | Usage or configuration error; nothing was sent. | will not help |
| `3` | Temporary failure: SignalHub was unreachable, timed out, or answered `429` or `5xx`. | may help later |

The command does not retry by itself. After a timeout the event may have
been stored even though no answer arrived, so sending it again may store it
twice, unless it has an idempotency key: a key that names this one event,
such as a CI run and attempt, or a UUID the script keeps. Sending the same
event with the same key again stores nothing new and prints the event stored
the first time, so exit status `3` can be retried safely:

```sh
key="nightly-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
for attempt in 1 2 3; do
  status=0
  signalhub send --idempotency-key "$key" --category BLOCKED --severity HIGH \
    --title "Nightly build failed" || status=$?
  [ "$status" -eq 3 ] || break
  sleep 30
done
exit "$status"
```

A key used before for a different event is rejected (exit status `1`); see
[docs/architecture.md](../../docs/architecture.md#idempotent-publishing).

Messages go to standard error, so a script can capture the ID:

```sh
id=$(signalhub send --category COMPLETED --severity NORMAL --title "Backup finished" \
  --context "$(hostname)" --meta "size=$(du -sh /backup | cut -f1)") || exit
```

## Library

```python
from datetime import datetime, timezone

from signalhub import Category, Severity, SignalHub

hub = SignalHub.from_env()  # or SignalHub("https://signalhub.example", api_key)

event = hub.publish(
    category=Category.ACTION_REQUIRED,  # or "ACTION_REQUIRED" / "action-required"
    severity=Severity.HIGH,
    title="Implementation review required",
    message="A human gate is waiting.",
    context="github.com/owner/repo",
    metadata={"pullRequest": 42},
    occurred_at=datetime.now(timezone.utc),  # or an ISO-8601 string
    idempotency_key="review-42-1",  # optional: repeating the call stores nothing new
)
print(event["id"], event["createdAt"])
```

`publish` returns the event as SignalHub stored it (a `dict`, with the
server's `id`, `producer` and `createdAt`). Errors are `SignalHubError`
subclasses:

| Error | When |
|---|---|
| `ConfigurationError` | The URL or API key is missing or unusable. |
| `ValidationError` | SignalHub rejected the event (`400`, `413`, `415`, or `422` for an idempotency key used for another event); `violations` lists `field` and `message`. |
| `AuthenticationError` | `401`: the key is invalid or revoked, or its producer is disabled. |
| `RequestError` | Any other error status; `status` holds it, and `temporary` is true for `429` and `5xx`. The two errors above are subclasses. |
| `UnreachableError` | No answer: connection refused, DNS failure, TLS error, or timeout. |

A timestamp without an offset raises `ValueError` before anything is sent,
as SignalHub rejects it as ambiguous, and so does an idempotency key that is
empty or not printable ASCII, which cannot be sent in a header.

With `idempotency_key`, a call that raised a temporary error (`temporary` is
true, or `UnreachableError`) can be repeated with the same arguments: if the
first call stored the event, the repeat returns it instead of storing another.

## Without the SDK

The HTTP API is the contract; the SDK adds nothing a producer cannot do
itself:

```sh
curl --fail-with-body "$SIGNALHUB_URL/api/v1/events" \
  -H "Authorization: Bearer $SIGNALHUB_API_KEY" -H 'Content-Type: application/json' \
  -d '{"category": "ACTION_REQUIRED", "severity": "HIGH",
       "title": "Implementation review required", "message": "A human gate is waiting."}'
```

## Development

From the repository root:

```sh
pip install ./sdk/python
python -m unittest discover --start-directory sdk/python/tests --top-level-directory sdk/python --verbose
ruff check . && ruff format --check .
```

The tests run against an in-process fake of the events endpoint on
`127.0.0.1`; they need no server, network or credentials. CI also publishes
with the command against the real backend in the Compose smoke test.
