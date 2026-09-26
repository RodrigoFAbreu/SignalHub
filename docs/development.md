# Development

SignalHub uses lightweight trunk-based development. `main` is always
releasable, and **every commit on `main` is a release**.

## Branching

- Never commit directly to `main`.
- Work on short-lived branches off the latest `main`, named by intent, e.g.
  `feat/event-ingestion`, `fix/duplicate-delivery`, `docs/producer-api`.
- Keep branches small. Merge within days, not weeks. Rebase on `main` as needed.
- If the PR for a branch has been merged, start follow-up work from the latest
  `main`. Never add commits to a merged branch.

## Pull requests

Changes reach `main` only through pull requests, and PRs are **squash merged**.
One merged PR becomes one commit on `main`, and that commit is one release.

A PR is ready to merge when:

- it is one coherent, vertically complete change: working code, tests,
  configuration, and documentation together;
- CI is green: the **CI** workflow and the **PR title** check;
- the PR template is filled in, including release impact and
  compatibility/migration notes;
- `main` would be releasable immediately after the merge.

Do not merge partial scaffolding, disabled tests, or "fix it in the next PR"
changes. If a feature is too large for one PR, split it into increments that
each work on their own, and keep unfinished behaviour unreachable (for example,
not wired into routing or not exposed in configuration) rather than broken.

## PR titles are release commits

The squash commit subject is the PR title, so the title must be a
[Conventional Commit](https://www.conventionalcommits.org/):

```
<type>[(scope)][!]: <description>
```

Allowed types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`,
`ci`, `chore`, `style`, `revert`. Scopes are lowercase, e.g. `feat(api): ...`.
Mark a breaking change with `!`, e.g. `feat(api)!: require event ids`.

The **PR title** check validates the title and prints its release impact. It
uses the same code as the release workflow (`scripts/release/release.py`).

Only the title matters for versioning. A `BREAKING CHANGE:` footer in the PR
body is **not** read, because squash commit bodies vary with repository
settings and PR description text. Use `!` in the title.

## Versioning

Versions are `vMAJOR.MINOR.PATCH` git tags.

| Title | Version 1.0.0 or later | Before 1.0.0 (now) |
|---|---|---|
| `feat!:` / any `type!:` (breaking) | major | **minor** |
| `feat:` | minor | minor |
| `fix:` and all other types | patch | patch |

**Pre-1.0 rule:** SignalHub is in initial development. A breaking change bumps
the minor version (`0.4.2` → `0.5.0`), as SemVer allows for `0.y.z`. A `!`
never produces `1.0.0` by accident. This means a `0.x` minor release may be
breaking; read the release notes. Moving to `1.0.0` is a deliberate decision.
It is made in a PR that changes the release policy in
`scripts/release/release.py` and its tests, and updates this document.

The first release has no previous tag, so it is computed from `0.0.0`. A `feat:`
bootstrap PR releases `v0.1.0`.

## Release process

Releases are fully automated by `.github/workflows/release.yml`. There is no
release PR and no manual step.

On every push to `main`:

1. The CI workflow runs again on the merged commit.
2. If CI passes, `release.py next-version` finds the highest `vX.Y.Z` tag
   reachable from the commit and the unreleased commits since it. The next
   version is that tag bumped by the largest bump among those commits.
3. `gh release create` tags the commit and publishes a GitHub release with
   generated notes.

Normally exactly one commit is unreleased, so each merge gets its own release.
Release runs are serialized. If a run fails, or a queued run is superseded by a
newer merge, the next successful run releases everything unreleased together at
the newer commit. Nothing is skipped silently, and a commit that failed CI on
`main` is never tagged on its own. Re-running a release for a commit that is
already tagged does nothing.

If a non-Conventional subject reaches `main` (which is only possible if the
title check was bypassed), the release workflow counts it as a patch and emits
a warning. It does not block all future releases.

## Definition of a releasable `main`

Every commit on `main` must:

- pass all CI checks;
- build and run for every component that exists in the repository;
- contain no known-broken, half-wired, or placeholder behaviour reachable by
  users or producers;
- have documentation that matches actual behaviour;
- contain no secrets or environment-specific credentials;
- include migrations for any persisted data or configuration change it
  introduces.

## Backend

The backend lives in `backend/`: a Quarkus service on Java 21, built with
Maven. See [architecture.md](architecture.md#backend-platform) for its design.

### Prerequisites

- **JDK 21** (for example Eclipse Temurin). Maven itself is not needed: the
  committed wrapper `./mvnw` downloads the pinned version.
- **Docker** with Docker Compose v2. Dev mode and the tests start PostgreSQL in
  a container through Quarkus Dev Services, and Compose runs the full stack.

All `./mvnw` commands below run in `backend/`.

### Dev mode

```sh
./mvnw quarkus:dev
```

Starts the service on <http://localhost:8080> with live reload. Quarkus Dev
Services starts a throwaway PostgreSQL container, applies the migrations, and
removes it on exit, so no database setup or credentials are needed. Swagger UI
is at <http://localhost:8080/q/swagger-ui> in dev mode only.

To register producers and clients in dev mode, enable the management API
with an admin token (see [Producers and API keys](#producers-and-api-keys)):

```sh
export SIGNALHUB_ADMIN_TOKEN=$(openssl rand -hex 32)
./mvnw quarkus:dev
```

### Build and test

```sh
./mvnw verify              # compile, test, format check, static analysis
./mvnw spotless:apply      # reformat Java sources (google-java-format)
./mvnw package -DskipTests # build target/quarkus-app/ only
```

`verify` is exactly what CI runs. The tests use real PostgreSQL (Dev Services
and Testcontainers), so Docker must be running. They cover liveness, readiness
with the database up and after it stops, Flyway startup migration and the
refusal of a newer schema (`SchemaVersionGuardTest`), the
production configuration, the OpenAPI document, and the events API: the HTTP
contract and validation (`EventApiTest`), the error body of every product
API error (`ApiErrorsTest`), the listing's order, filters,
pagination and parameter validation (`EventListApiTest`, with the cursor
format in `EventCursorTest`), and what reaches PostgreSQL, including the
schema's own constraints (`EventPersistenceTest`). Producer
authentication is covered by `EventAuthenticationTest` (every way publishing
can be rejected, rotation, revocation, disabling, and that the payload cannot
claim a producer), `ProducerAdminApiTest` and `AdminApiDisabledTest` (the
management API, the listing, and their admin-token guard), `ProducerPersistenceTest` (only
hashes are stored), `ProducerMigrationTest` (upgrading a database that holds
events from before authentication), and unit tests for the key format, bearer
parsing and admin token (`ApiKeysTest`, `BearerTokenTest`, `AdminTokenTest`).
Clients are covered by `ClientApiTest` (registration, revocation, client keys
reading the listing, and push targets), `PushPreferencesApiTest` (setting,
replacing and validating push preferences), `ClientPersistenceTest` (hashes
only, and the schema's push-target and push-preference constraints),
`ClientKeysTest` (the key format) and `PushPreferencesTest` (which events
preferences let through). Push delivery is covered by `PushDeliveryTest` (every outcome,
through `FakePushProvider`, a test-only provider named `fake`) and
`PushProvidersTest` (provider name checks at startup). The FCM provider is
covered by `FcmPushProviderTest` (request format, access-token signing and
caching, and the mapping of every FCM error), `FcmCredentialsTest` (reading
the key file, never echoing the key) and `FcmDeliveryTest` (the `fcm` provider
active in a running backend), all against `FakeFcm`, an in-process stand-in
for Google's token endpoint and the FCM API with a key generated per run.
Event-triggered dispatch is covered by `EventPushDispatchTest` (the outbox
row is written with the event, every client with a target gets one push
unless its preferences exclude the event, expired claims are dispatched
again, temporary failures are retried with backoff up to the last attempt,
and a retry honours preferences changed meanwhile), `EventPushScheduleTest` (the dispatcher
runs on its own timer) and `EventPushMessagesTest` (shortening the body). The
test profile turns the scheduler off so tests run the dispatcher directly. No
test needs a real push provider, network access or credentials.
`StartupDiagnosticsTest` covers the startup configuration summary (what it
names, that it holds no secret, and the database URL's redaction), and
`ProductionConfigTest` how the prod profile reads its settings, including
opt-in JSON logs.
The test profile uses a fixed, test-only admin token from
`application.properties`.

Formatting is [google-java-format](https://github.com/google/google-java-format)
through Spotless, and static analysis is [SpotBugs](https://spotbugs.github.io/)
plus `javac -Xlint:all` with warnings as errors. Both fail `verify`.

### Migrations

Flyway is the only way the schema changes. Migrations are SQL files in
`backend/src/main/resources/db/migration`, named `V<version>__<description>.sql`,
and are applied automatically at startup in every mode (dev, test, Compose,
production). A misnamed migration or one edited after it was applied fails
startup, and so does a database that a newer release has migrated (a
migration this code does not have; see `SchemaVersionGuard`). Hibernate
never creates or alters tables. There is no separate migrate
command: start the service (dev mode or Compose) to migrate its database. The
migrations are listed in
[`db/migration/README.md`](../backend/src/main/resources/db/migration/README.md).

### Docker Compose

`compose.yaml` at the repository root runs the backend image (built from
`backend/Dockerfile`) and PostgreSQL 17 with a persistent volume:

```sh
cp .env.example .env          # set SIGNALHUB_DB_PASSWORD and SIGNALHUB_ADMIN_TOKEN
docker compose up --build --wait
curl http://localhost:8080/q/health/ready
docker compose down           # keeps the database volume; add --volumes to delete it
```

The backend waits for PostgreSQL to be healthy, applies migrations, and is
reported healthy once readiness passes. The HTTP port is published on
`127.0.0.1` only (`SIGNALHUB_HTTP_PORT`, default 8080); the database port is
not published.

The stack runs on x86-64 (`amd64`) and 64-bit ARM (`arm64`, such as a
Raspberry Pi 5 with a 64-bit OS): the base images are multi-platform, so
`docker compose up --build` builds the backend image for the host's
architecture. CI runs the Compose smoke test natively on both.

To reach SignalHub from other machines (phones, producers), enable the
TLS reverse proxy (`COMPOSE_PROFILES=proxy` with `SIGNALHUB_DOMAIN` and
`SIGNALHUB_TLS` in `.env`); see [deployment.md](deployment.md).

Upgrade to a new release, and monitor health, as in
[deployment.md](deployment.md#upgrades). Back up and restore the database
with the commands in [Backup and restore](architecture.md#backup-and-restore), and see
[Resources](architecture.md#resources) for memory and CPU limits and
database growth.

### Endpoints

| Path | Purpose |
|---|---|
| `/api/v1/events` | `POST`: publish an event, with a producer API key. See [Events API](#events-api). |
| `/api/v1/events` | `GET`: list events, newest first, with a client key or the admin token. See [Events API](#events-api). |
| `/api/v1/events/{id}` | `GET`: read an event by its ID, with a client key or the admin token. |
| `/api/v1/admin/producers/...` | Producer management, with the admin token. See [Producers and API keys](#producers-and-api-keys). |
| `/api/v1/admin/clients/...` | Client management, with the admin token. See [Clients](#clients). |
| `/api/v1/client/...` | A client's own registration and push target, with its client key. See [Clients](#clients). |
| `/q/health/live` | Liveness: 200 while the process runs. No dependency checks. |
| `/q/health/ready` | Readiness: 200 when PostgreSQL is reachable, 503 otherwise. |
| `/q/health` | Both of the above combined. |
| `/q/openapi` | OpenAPI document (YAML; `?format=json` for JSON). |
| `/q/metrics` | Prometheus metrics: HTTP, JVM, database pool, events and push delivery. See [Metrics](architecture.md#metrics). |
| `/q/swagger-ui` | Swagger UI, dev mode only. |

### Producers and API keys

Producers, keys, and the admin token are described in
[architecture.md](architecture.md#producers-and-authentication). The
management API is enabled only when `SIGNALHUB_ADMIN_TOKEN` is set (at least
32 characters). In the shell you run curl from, set `ADMIN_TOKEN` to the same
value, for example from `.env`:

```sh
ADMIN_TOKEN=$(sed -n 's/^SIGNALHUB_ADMIN_TOKEN=//p' .env)
```

Register a producer. The response contains its API key, **shown only this
once**:

```sh
curl -s http://localhost:8080/api/v1/admin/producers \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name": "ci-build-runner"}'
```

```json
{
  "producer": {
    "id": "01a0d96b-4298-7ce4-981a-5ed853d075b9",
    "name": "ci-build-runner",
    "createdAt": "2026-09-25T16:34:40.404295Z",
    "disabledAt": null,
    "keys": [
      {"id": "b49cd36a-84ed-4581-b4bb-9b89f170a57c", "createdAt": "2026-09-25T16:34:40.417295Z", "revokedAt": null}
    ]
  },
  "keyId": "b49cd36a-84ed-4581-b4bb-9b89f170a57c",
  "apiKey": "shpk1_b49cd36a84ed4581b4bb9b89f170a57c_<secret>"
}
```

Give `apiKey` to the producer through its own secret store, never through the
repository. Then manage it (`$PRODUCER` and `$KEY` are the IDs above):

```sh
H="Authorization: Bearer $ADMIN_TOKEN"
API=http://localhost:8080/api/v1/admin/producers
curl -s "$API" -H "$H"                                     # list producers and key records
curl -s "$API/$PRODUCER" -H "$H"                           # one producer
curl -s -X POST "$API/$PRODUCER/keys" -H "$H"              # issue another key (rotation, step 1)
curl -s -X POST "$API/$PRODUCER/keys/$KEY/revoke" -H "$H"  # revoke the old key (rotation, step 2)
curl -s -X POST "$API/$PRODUCER/disable" -H "$H"           # block all its keys
curl -s -X POST "$API/$PRODUCER/enable" -H "$H"            # unblock its unrevoked keys
```

### Clients

Clients (the owner's app installations) and their keys are described in
[architecture.md](architecture.md#clients). Register one with the admin
token; the response contains its client key, **shown only this once**:

```sh
curl -s http://localhost:8080/api/v1/admin/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name": "Pixel 8"}'
```

```json
{
  "client": {
    "id": "01a0da2c-1f3e-7a51-8d0c-6b1f2e3d4c5b",
    "name": "Pixel 8",
    "createdAt": "2026-09-25T18:02:11.108811Z",
    "revokedAt": null,
    "pushTarget": null,
    "pushPreferences": {
      "enabled": true,
      "minimumSeverity": "LOW",
      "mutedCategories": [],
      "mutedProducerIds": []
    }
  },
  "clientKey": "shck1_01a0da2c1f3e7a518d0c6b1f2e3d4c5b_<secret>"
}
```

Configure the client installation with `clientKey`. It then reads events and
manages its own push target and push preferences (`$CLIENT_KEY` is the key
above):

```sh
C="Authorization: Bearer $CLIENT_KEY"
curl -s http://localhost:8080/api/v1/events -H "$C"            # the inbox
curl -s http://localhost:8080/api/v1/client -H "$C"            # its own registration
curl -s -X PUT http://localhost:8080/api/v1/client/push-target -H "$C" \
  -H 'Content-Type: application/json' -d '{"provider": "fcm", "token": "<provider token>"}'
curl -s -X DELETE http://localhost:8080/api/v1/client/push-target -H "$C"
# push only HIGH and CRITICAL events, and nothing that is merely INFO
curl -s -X PUT http://localhost:8080/api/v1/client/push-preferences -H "$C" \
  -H 'Content-Type: application/json' \
  -d '{"minimumSeverity": "HIGH", "mutedCategories": ["INFO"]}'
curl -s -X PUT http://localhost:8080/api/v1/client/push-preferences -H "$C" \
  -H 'Content-Type: application/json' -d '{}'   # back to pushing every event
```

The operator lists, inspects and revokes clients (`$CLIENT` is the ID above):

```sh
H="Authorization: Bearer $ADMIN_TOKEN"
API=http://localhost:8080/api/v1/admin/clients
curl -s "$API" -H "$H"                          # all clients
curl -s "$API/$CLIENT" -H "$H"                  # one client
curl -s -X POST "$API/$CLIENT/revoke" -H "$H"   # revoke it and drop its push target
```

Every published event that the client's
[push preferences](architecture.md#push-preferences) allow is then pushed to
the target (see [Push dispatch](architecture.md#push-dispatch)); every event
stays in the inbox either way. The client app does all of
this itself; see [Client](#client).

### Events API

The event model, validation rules, and timestamp and metadata semantics are
described in [architecture.md](architecture.md#events). The OpenAPI document
(`/q/openapi`, or Swagger UI in dev mode) has the full schema and examples.
Try it against dev mode or Compose, with a key from
[Producers and API keys](#producers-and-api-keys) in `API_KEY`:

```sh
curl -i http://localhost:8080/api/v1/events \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{
        "context": "signalhub",
        "category": "BLOCKED",
        "severity": "HIGH",
        "title": "Nightly build failed",
        "message": "3 of 412 tests failed on main.",
        "metadata": {"pipeline": "nightly", "run": 1842},
        "occurredAt": "2026-09-25T14:03:00+02:00"
      }'
```

```http
HTTP/1.1 201 Created
Location: http://localhost:8080/api/v1/events/01a0d931-9c33-7989-a9ea-adb6724470e6
Content-Type: application/json;charset=UTF-8

{
  "id": "01a0d931-9c33-7989-a9ea-adb6724470e6",
  "producer": {"id": "01a0d96b-4298-7ce4-981a-5ed853d075b9", "name": "ci-build-runner"},
  "context": "signalhub",
  "category": "BLOCKED",
  "severity": "HIGH",
  "title": "Nightly build failed",
  "message": "3 of 412 tests failed on main.",
  "metadata": {"pipeline": "nightly", "run": 1842},
  "occurredAt": "2026-09-25T12:03:00Z",
  "createdAt": "2026-09-25T15:31:42.209368Z"
}
```

Read it back, including after restarting the service, with a client key or
the admin token (a producer key gets `401`):

```sh
curl http://localhost:8080/api/v1/events/01a0d931-9c33-7989-a9ea-adb6724470e6 \
  -H "Authorization: Bearer $ADMIN_TOKEN"
```

List events, newest first, with a client key (see [Clients](#clients)) or the
admin token (see [architecture.md](architecture.md#listing-events) for every
parameter):

```sh
H="Authorization: Bearer $CLIENT_KEY"
curl -s "http://localhost:8080/api/v1/events?limit=20" -H "$H"
curl -s "http://localhost:8080/api/v1/events?severity=HIGH&severity=CRITICAL&createdFrom=2026-09-25T00:00:00Z" -H "$H"
curl -s "http://localhost:8080/api/v1/events?producerId=$PRODUCER&limit=20&cursor=$NEXT_CURSOR" -H "$H"
```

```json
{
  "items": [
    {"id": "01a0d931-9c33-7989-a9ea-adb6724470e6", "producer": {"id": "01a0d96b-4298-7ce4-981a-5ed853d075b9", "name": "ci-build-runner"}, "category": "BLOCKED", "severity": "HIGH", "title": "Nightly build failed", "createdAt": "2026-09-25T15:31:42.209368Z", "...": "..."}
  ],
  "nextCursor": "MToxNzkwMzUwMzAyMjA5MzY4OjAxYTBkOTMxLTljMzMtNzk4OS1hOWVhLWFkYjY3MjQ0NzBlNg"
}
```

`nextCursor` is `null` on the last page. Pass it back unchanged, with the same
filters, to read the next page.

Mark events read or unread for all clients, and count unread events (see
[architecture.md](architecture.md#read-state)):

```sh
curl -s -X PUT "http://localhost:8080/api/v1/events/$EVENT/read" -H "$H"      # the event, with readAt
curl -s -X DELETE "http://localhost:8080/api/v1/events/$EVENT/read" -H "$H"   # readAt is null again
curl -s http://localhost:8080/api/v1/events/read -H "$H" \
  -H 'Content-Type: application/json' -d "{\"through\": \"$EVENT\"}"       # {"marked": 12}
curl -s http://localhost:8080/api/v1/events/unread-count -H "$H"              # {"unread": 0}
```

Without a valid key (missing, malformed, unknown, revoked, or of a disabled
producer) the answer is always the same `401`:

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: Bearer realm="signalhub"

{"title": "Unauthorized", "status": 401, "violations": []}
```

Invalid input gets a `400` that names each offending field:

```json
{
  "title": "Invalid request",
  "status": 400,
  "violations": [
    {"field": "category", "message": "must be one of [ACTION_REQUIRED, BLOCKED, COMPLETED, INFO]"}
  ]
}
```

Other errors under `/api/` have the same body with no violations, for
example `{"title": "Method Not Allowed", "status": 405, "violations": []}`;
only a `413` for an oversized body has none (see
[architecture.md](architecture.md#http-api)).

### Configuration

Configuration is `backend/src/main/resources/application.properties`, which
holds non-secret defaults only. Every property can be overridden by its Quarkus
environment variable (for example `QUARKUS_HTTP_PORT`).

| Profile | Used by | Database |
|---|---|---|
| `dev` | `./mvnw quarkus:dev` | Dev Services container |
| `test` | `./mvnw verify` | Dev Services or Testcontainers |
| `prod` | the packaged app and Docker image | environment variables below |

In `prod` the service refuses to start unless these are set:

| Variable | Example |
|---|---|
| `SIGNALHUB_DB_URL` | `jdbc:postgresql://postgres:5432/signalhub` |
| `SIGNALHUB_DB_USERNAME` | `signalhub` |
| `SIGNALHUB_DB_PASSWORD` | from your secret store |

Optional in every profile:

| Variable | Effect |
|---|---|
| `SIGNALHUB_ADMIN_TOKEN` | Enables the management API for producers and clients, and lets the operator list events. At least 32 characters (`openssl rand -hex 32`); shorter stops startup. Unset or empty disables the management API; clients keep reading events with their keys. |
| `SIGNALHUB_EVENTS_RETENTION` | How long events are kept, a duration of at least `1d` such as `365d`; older events are deleted every hour. Shorter stops startup. Unset or empty keeps events forever (the default). See [Retention](architecture.md#retention). |
| `SIGNALHUB_LOG_JSON` | `true` writes console logs as JSON, one object per line, for log collectors; default `false` (plain text). See [Logs](architecture.md#logs). |
| `SIGNALHUB_PUSH_DISPATCH_INTERVAL` | How often the push dispatcher looks for new events to push; default `2s`. See [Push dispatch](architecture.md#push-dispatch). |
| `SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE` | Path to a Firebase service account key file (JSON). Enables push through Firebase Cloud Messaging (provider `fcm`); an unreadable or invalid file stops startup. Unset or empty: no `fcm` provider, and `fcm` push targets are reported as unsupported. See [Firebase Cloud Messaging](#firebase-cloud-messaging). |

Compose derives them from `.env` (see `.env.example`). Never commit `.env`.
Log levels use the standard Quarkus variables, for example
`QUARKUS_LOG_LEVEL=DEBUG`. On startup the log shows a `Configuration: ...`
line with the effective settings, without secrets.

### Firebase Cloud Messaging

To send real pushes, create a Firebase project, then in its console open
*Project settings → Service accounts → Generate new private key*. Keep the
downloaded JSON file outside the repository (it is a credential) and mount it into the backend read-only, for example
with a git-ignored `compose.override.yaml` next to `compose.yaml`:

```yaml
services:
  backend:
    environment:
      SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE: /run/secrets/fcm.json
    volumes:
      - /path/outside/the/repo/fcm-service-account.json:/run/secrets/fcm.json:ro
```

The container runs as UID 10001, which must be able to read the file. On
startup the log shows `FCM push enabled for Firebase project ...` and
`Push providers: [fcm]`. Clients register their FCM registration token with
`PUT /api/v1/client/push-target` and provider `fcm`. From then on, every
published event is pushed to them.

## Client

The client app lives in `client/`: one Flutter codebase for Android and iOS.
See [architecture.md](architecture.md#client-application) for its design and
[`client/README.md`](../client/README.md) for running it against a backend
and setting up push with your Firebase project.

### Prerequisites

- **Flutter 3.47.5** (stable), the version CI pins in `FLUTTER_VERSION` in
  `.github/workflows/ci.yml`. It includes Dart.
- For Android builds: the Android SDK (Android Studio or the command-line
  tools) and JDK 17.
- For iOS builds: macOS with Xcode.

Dependencies are locked in `client/pubspec.lock`. Update them with
`flutter pub upgrade` and commit the lock file.

All commands below run in `client/`.

### Build and test

```sh
flutter pub get --enforce-lockfile            # exactly the locked dependencies
dart format --output=none --set-exit-if-changed .   # formatting check (`dart format .` fixes)
flutter analyze                               # static analysis (lints in analysis_options.yaml)
flutter test                                  # unit and widget tests
flutter build apk --debug                     # Android build
flutter build ios --debug --no-codesign       # iOS build (macOS only)
```

The tests need no device, network or credentials: `SignalHubApi` runs
against `FakeBackend`, an in-memory stand-in for the client API built on the
`http` package's `MockClient`, and push against `FakePushService`. They cover
the API client (paths, bearer key, cursors, reading one event, push-target
bodies, push-preference bodies, error mapping), the models (every documented field, unknown enum
values, contract violations), server address and key validation, the app
controller (setup, restart, revoked key, unreachable server, push
permission, token refresh, pushes re-reading the inbox, paging and its
failures, opening a tapped notification's event, disconnect), the Firebase
options from build-time values, and the screens in widget tests (inbox,
paging while scrolling, event details, opening from a notification) and
read state (the API calls, the unread count, marking read on opening,
marking unread, marking all read up to the newest event shown, and their
failures), and push preferences (saving each change, what the server
stored, muted producers without inbox events, failures, a server without
them). Builds without Firebase options run without push.

## Python SDK

The producer package and `signalhub` command live in `sdk/python/`. See
[architecture.md](architecture.md#producer-sdk-and-cli) for its design and
[`sdk/python/README.md`](../sdk/python/README.md) for installing and using it.
It needs Python 3.10 or later and has no dependencies beyond the standard
library, so there is no lock file; the build backend is pinned in
`sdk/python/pyproject.toml`.

From the repository root:

```sh
pip install ./sdk/python   # the package and the `signalhub` command
python -m unittest discover --start-directory sdk/python/tests --top-level-directory sdk/python --verbose
```

Formatting and lints are the repository's `ruff check .` and
`ruff format --check .`. The tests need no server, network or credentials:
they run the package and the command against `FakeSignalHub`, an in-process
HTTP stand-in for the events endpoint on `127.0.0.1`. They cover the request
(path, bearer key, body, optional fields, timestamps, category and severity
names), configuration from options, the environment and key files, error
mapping (validation violations, `401`, `404`, `413`, `429` and `5xx`, non-JSON
answers, an unreachable server) and the command's output and exit statuses.
CI runs them on Python 3.10 and 3.12, and the Compose smoke test publishes
with the command against the real backend.

## Integration examples

`examples/` holds small producers (shell, a disk monitor, GitHub Actions, a
coding-agent hook, a usage-threshold monitor) that use only the public API;
see [`examples/README.md`](../examples/README.md). They are copied and
adapted by owners, not installed. After `pip install ./sdk/python`, from the
repository root:

```sh
shellcheck examples/*/*.sh
python -m unittest discover --start-directory examples/tests --verbose
```

The tests need `sh`, `bash`, `curl` and `jq`, but no server, network or
credentials: each example runs as a subprocess against an in-process fake of
the events endpoint on `127.0.0.1`, including the `run:` script of the
example workflow. The example workflow is linted by actionlint with the
repository's own, and the Compose smoke test runs the examples against the
real backend, each as its own producer.

## Local validation

CI runs:

```sh
# Repository tooling
pip install ruff==0.16.9
ruff check .
ruff format --check .
python -m unittest discover --start-directory scripts/release --verbose
# Python SDK, also run with python3.10 in CI
pip install ./sdk/python && signalhub send --help
python -m unittest discover --start-directory sdk/python/tests --top-level-directory sdk/python --verbose
# Integration examples (need the SDK, curl and jq)
shellcheck examples/*/*.sh
python -m unittest discover --start-directory examples/tests --verbose
# Lints GitHub Actions workflows and the example workflow (needs Docker):
docker run --rm --volume "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color .github/workflows/*.yml examples/github-actions/*.yml

# Client (in client/, needs Flutter; the iOS build needs macOS)
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --debug --no-codesign

# Backend (needs Docker)
(cd backend && ./mvnw verify)
# Container smoke test: the "Backend container" jobs in .github/workflows/ci.yml,
# on x86-64 and natively on ARM64, check that the images match the runner's
# architecture and start the stack with `docker compose up --build --wait` and a random admin
# token, the resource limits of architecture.md#resources and the TLS proxy (with Caddy's own CA), checks liveness, readiness, OpenAPI and metrics, registers a producer, checks
# that publishing without a valid key gets 401, publishes an event with the key
# and reads it back after restarting the backend, lists it with the admin
# token (and expects 401 without it), lists it over HTTPS through the proxy
# and expects 404 there for management, health, metrics and OpenAPI, however
# the path is spelled, and a redirect from plain HTTP, registers a client that lists the event
# with its key, marks it read and counts no unread events, sets a push
# target, revokes the client and expects 401, publishes with the Python command
# and reads the event back (and expects exit status 1 with an invalid key),
# restarts the backend with JSON logs and checks that every line is JSON, that
# the startup summary is logged, and that no secret is, backs up the database,
# restores it into an empty one and checks that events from before the backup
# (and only those) are back, the producer key still works and the proxy kept
# its CA, and that restoring over existing data fails, runs the integration
# examples as four new producers and lists their events, revokes the producer
# key and expects 401, stops PostgreSQL and expects readiness 503, and checks that the image refuses to start without database
# settings. The "Backend container (upgrade from the latest release)" job starts
# the latest release tag with a producer, a client and a read event, backs up,
# upgrades in place to the commit under test as in docs/deployment.md#upgrades,
# checks the data, keys, migrations and health, and rolls back by restoring the
# backup with the release. The "End-to-end (producer to push and client inbox)"
# job starts the stack with FCM push enabled through a throwaway service account
# key and scripts/e2e/fake_fcm.py (a stand-in for Google's token endpoint and
# the FCM HTTP v1 API, on the runner), registers a producer and two clients,
# publishes a low and a high severity event with the Python command, checks
# that the client whose preferences want only HIGH gets exactly one FCM message
# with the event's ID, that FCM's UNREGISTERED answer removes the other client's
# push target, and the delivery metrics, then opens the pushed event with the
# client key, lists both events in the inbox and marks the pushed one read.
```

Each new component adds its own build, lint, and test commands to CI and to
this section in the PR that introduces it.

## Repository settings (GitHub)

These settings are required for the model above and live outside the
repository:

- Allow **squash merging** only. Disable merge commits and rebase merging.
- Default squash commit message: **Pull request title** (optionally with
  description). Without this, a single-commit PR uses its commit message
  instead of the validated PR title.
- Protect `main`: require a pull request, and require the status checks
  `Python (lint + test)`, `GitHub Actions lint`, `Backend (build + test)`,
  `Backend container (Compose smoke test)`, `Backend container (Compose
  smoke test, ARM64)`, `Backend container (upgrade from the latest
  release)`, `End-to-end (producer to push and client inbox)`, `Client (analyze + test +
  Android build)`, `Client (iOS build)`, and `Conventional Commit title`.
  Require branches to be up to date before merging.
- Actions workflow permissions must allow `contents: write` for the release
  job (it requests this explicitly).
