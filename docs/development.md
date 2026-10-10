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

| Title | Bump |
|---|---|
| `feat!:` / any `type!:` (breaking) | major |
| `feat:` | minor |
| `fix:` and all other types | patch |

SignalHub follows SemVer from `1.0.0`: a breaking change of the public
contract ([architecture.md](architecture.md#compatibility)) is a major
release, and only a title with `!` produces one. The version is the whole
repository's; the backend, the app and the SDK have no versions of their own.

Before `1.0.0` a breaking change bumped the minor version (`0.4.2` →
`0.5.0`), so a `0.x` minor release may be breaking. `1.0.0` was a deliberate
decision of the maintainer, released by the PR that removed that rule.

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
3. The backend image is built from the commit on an x86-64 and an ARM64
   runner, each natively, with `scripts/release/build-image.sh`, which bakes
   in the version (without `v`), the commit and the commit's time: as
   `SIGNALHUB_VERSION` and `SIGNALHUB_REVISION` for the backend (see
   [Version](architecture.md#version)) and as the OCI labels `version`,
   `revision`, `created` and `source`. Each platform is pushed to GHCR by
   digest, with BuildKit's provenance (`mode=max`) and SBOM attestations,
   stored beside the image in the registry.
4. The two are tagged as one multi-platform image,
   `ghcr.io/rodrigofabreu/signalhub:X.Y.Z`. Only the exact version is
   tagged: no `latest` and no `X.Y`, so an image reference always names one
   release, and the docs always name an exact version.
5. On both platforms the tagged image is pulled and checked by
   `scripts/release/check-image.sh`: the labels, the architecture, and,
   started with PostgreSQL, the version and commit at `/q/info` and in the
   startup summary.
6. `scripts/release/deployment_files.py` packs the release's deployment
   files, `signalhub-X.Y.Z-deployment.tar.gz`: the commit's `compose.yaml`,
   `.env.example` and `proxy/Caddyfile`, with `compose.yaml` running the
   image just published, by tag and digest, instead of building the backend
   (see [deployment.md](deployment.md#setup)).
7. `scripts/release/sdk_files.py` builds the Python SDK's wheel and source
   archive (`signalhub-X.Y.Z-py3-none-any.whl`, `signalhub-X.Y.Z.tar.gz`)
   from a copy of `sdk/python/` with the version in place of the development
   placeholder `0.0.0.dev0` of its `pyproject.toml`, then installs the wheel
   into a new virtual environment and checks that `signalhub --version`
   prints `SignalHub X.Y.Z`. A `SHA256SUMS` file lists the checksums of the
   deployment files and the SDK's files.
8. In parallel with the image, `scripts/release/app_files.py` builds the
   Android app, `SignalHub-X.Y.Z.apk`, from the commit: a release-mode APK
   with `versionName` `X.Y.Z`, a `versionCode` derived from the version
   (below), the version and commit compiled in for the *This device*
   group of Settings, and no Firebase options (the app reads its
   server's). It is signed with SignalHub's release key, which the job rebuilds from the
   repository's secrets (below) in a directory it removes at its end. The
   script then checks the APK: package, `versionName`, `versionCode`, not
   debuggable, the commit in the compiled code, a valid v2 or v3 signature
   by exactly one signer, and that signer being the release key's
   certificate, never a debug key. GitHub records a build provenance
   attestation for it (`gh attestation verify SignalHub-X.Y.Z.apk --repo
   RodrigoFAbreu/SignalHub`). Without the key the release fails before
   tagging; it never attaches an unsigned or debug-signed app.
9. `gh release create` tags the commit and publishes a GitHub release whose
   notes name the image and its digest and the app's signing certificate,
   followed by the generated notes, with the deployment files, the SDK's
   files, the app and `SHA256SUMS` (all of them) attached.

The release is complete only when its GitHub release exists. If a run fails
after pushing the image but before the GitHub release, the version is not
released: the git tag does not exist, and re-running the workflow, or the
next merge's run, builds and pushes that version's image again from its own
commit. An image tag of a published release is never pushed again, because
the next run computes a higher version. The deployment files name the image
by its digest, so they run exactly the image the release checked. Releases
up to v1.1.0 attach no deployment files, releases up to v1.2.0 no SDK
files, and releases up to v1.6.0 no app.

The app's `versionCode` is `MAJOR × 1000000 + MINOR × 1000 + PATCH`
(`1.7.0` is `1007000`), so every release's is higher than the one before
and Android installs it as an update. The script refuses a version with a
`MINOR` or `PATCH` above 999, which the rule could not order; a release
reaching one needs a new rule first. Local builds keep `pubspec.yaml`'s
build number, 1.

The first release that publishes an image creates the GHCR package
`signalhub`, private at first. Making it public, so that pulling needs no
login, is a one-time step for the repository owner: on GitHub, *Packages* →
`signalhub` → *Package settings* → *Change visibility* → *Public*. The
release itself logs in to pull, so it works either way.

Pull requests build the image the same way on both platforms (the
`Backend image (release build)` jobs), with the test version `0.0.0-ci`, and
run the same checks, without pushing. The `Python (lint + test)` job builds
the SDK's files with `sdk_files.py` and the test version `0.0.0+ci` (a
version Python packaging accepts). The `Client (analyze + test + Android
build)` job builds and checks the app with `app_files.py` and the test
version `0.0.0-ci` (`versionCode` 1), signed with a throwaway key it makes
for the run. The upgrade and fresh-install jobs pack
deployment files naming that image and install from them, as operators do
with a release's. Any other build of the image, such as
`docker compose up --build`, has no version and reports itself as a
development build.

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

The backend lives in `backend/`: a Quarkus service on Java 25, built with
Maven. See [architecture.md](architecture.md#backend-platform) for its design.

### Prerequisites

- **JDK 25** (for example Eclipse Temurin). Maven itself is not needed: the
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
Users and subscriptions are covered by `UserAdminApiTest` (inviting, roles, revoking, subscribing), `ProducerVisibilityApiTest` (owners, visibility, allow-lists), `EventVisibilityApiTest` (an event reaches only subscribed users, in the inbox, the unread count, by ID and by push; per-user read state), `DeviceApiTest`, `DevicePairingApiTest` and `ClientDeletionApiTest` (what each role may do with devices) and `UsersMigrationTest` (upgrading a single-owner database). Clients are covered by `ClientApiTest` (registration, revocation, client keys
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
runs on its own timer), `EventPushMessagesTest` (shortening the body) and
`EventDeliveryApiTest` (each event's delivery records: every outcome with its
reason, each filtering preference, retries as further attempts, the admin
token, and a failure to record changing no push), with
`EventDeliveriesMigrationTest` for their migration. The
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
`backend/Dockerfile`) and PostgreSQL 18 with a persistent volume, building
the backend from source:

```sh
cp .env.example .env          # set SIGNALHUB_DB_PASSWORD and SIGNALHUB_ADMIN_TOKEN
docker compose up --build --wait
curl http://localhost:8080/q/health/ready
docker compose down           # keeps the database volume; add --volumes to delete it
```

A local database volume made before the move to PostgreSQL 18 does not
start with it: PostgreSQL logs that there is data of an older version and
exits. Delete it with `docker compose down --volumes`, or move its data as
in [deployment.md](deployment.md#a-new-postgresql-major-version).

Deployments run a release's published image instead, from its deployment
files (see [deployment.md](deployment.md#deployment-files)): this
`compose.yaml` with the image in place of the build, so they build nothing.

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

### Clearing local test data

Testing on a device publishes real events into the local database, and
they stay in the inbox. These commands are for a local development stack
only; never run them against a deployment whose events you want to keep.

To delete the events of one test producer and keep everything else
(producers, clients, their keys, read state of other events, push
preferences), name the producer and run, with the stack up:

```sh
docker compose exec -T postgres sh -c 'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1' <<'SQL'
DELETE FROM events
WHERE producer_id = (SELECT id FROM producers WHERE name = 'device-test');
SQL
```

It prints `DELETE` and the number of events deleted; their pending pushes
and retries go with them. The app shows the change on its next refresh.
Wrap the statement in `BEGIN;` and `ROLLBACK;`, with a `SELECT count(*)`
instead, to see what it would delete first.

To start over from an empty database instead:

```sh
docker compose down
docker volume rm signalhub_postgres-data   # compose.yaml names the project signalhub
docker compose up --build --wait
```

**This permanently deletes the local database**: every event, producer,
client and key. Producer keys and client keys issued before stop working,
so register the producer and the client again (see
[Producers and API keys](#producers-and-api-keys) and [Clients](#clients))
and set the app up with the new client key. Removing only that volume keeps
the proxy's certificates; `docker compose down --volumes` would delete
those too. Take a [backup](architecture.md#backup-and-restore) first if in
doubt.

### Endpoints

| Path | Purpose |
|---|---|
| `/api/v1/events` | `POST`: publish an event, with a producer API key. See [Events API](#events-api). |
| `/api/v1/events` | `GET`: list events, newest first, with a client key or the admin token. See [Events API](#events-api). |
| `/api/v1/events/{id}` | `GET`: read an event by its ID, with a client key or the admin token. |
| `/api/v1/admin/producers/...` | Producer management, with the admin token, and `POST /{id}/events`: a test event sent as the producer. See [Producers and API keys](#producers-and-api-keys). |
| `/api/v1/admin/users/...` | User management, with the admin token: invite, rename, set the role, revoke, subscribe. See [Users](#users). |
| `/api/v1/admin/clients/...` | Client management, with the admin token. See [Clients](#clients). |
| `/api/v1/admin/events/...` | With the admin token: `GET /{id}/deliveries` how the event's push went to each device (see [Delivery records](architecture.md#delivery-records)); deleting events: `DELETE /{id}` one event; `POST /delete` a selection, a producer's events or events older than a time, with a dry run. See [Events API](#events-api). |
| `/api/v1/admin/status` | `GET`: whether push is configured, the push backlog, retries given up and the retention period, with the admin token; the admin page's Status section. See [Service status](architecture.md#service-status). |
| `/api/v1/admin/pairings` | `POST`: create a pairing code for a new device, with the admin token; `GET /{id}`: whether it was used, and by which device. See [Pairing a device](#pairing-a-device). |
| `/api/v1/pairing` | `POST`: a device redeems a pairing code and gets its client key; the owner's other devices get a push. See [Pairing a device](#pairing-a-device). |
| `/admin/` | The admin page, in sections (`#devices`, `#users`, `#producers`, `#events`, `#status`): with the admin token, lists every device with its user to rename it or revoke it, and to delete it once revoked, and creates a pairing code for a user shown as a QR code to scan, copy or download; lists every user with their role, devices, producers and subscriptions, invites users, renames them, sets their role (admin included: only here), subscribes them and revokes them; lists every producer with its owner, who sees it, its keys and its last event, creates producers for a user, edits who sees them, issues and revokes keys, and disables and enables producers; lists events a page at a time with the inbox's filters and opens one (`#events/<id>`) to read it, see how its push went to each device and mark it read or unread, sends a test event as an enabled producer and links to it, and deletes one, the events ticked on a page, or every event of a producer or received before a day, after a confirmation stating their count; and shows whether SignalHub is working (release, health, push, backlog, failed pushes, retention, latest event). Not forwarded by the proxy. `/connect/`, its earlier name, is gone (`404`). See [Clients](#clients) and [Pairing a device](#pairing-a-device). |
| `/api/v1/client/...` | A client's own registration and push target, with its client key. See [Clients](#clients). |
| `/q/health/live` | Liveness: 200 while the process runs. No dependency checks. |
| `/q/health/ready` | Readiness: 200 when PostgreSQL is reachable, 503 otherwise. |
| `/q/health` | Both of the above combined. |
| `/q/openapi` | OpenAPI document (YAML; `?format=json` for JSON). |
| `/q/metrics` | Prometheus metrics: HTTP, JVM, database pool, events and push delivery. See [Metrics](architecture.md#metrics). |
| `/q/info` | The release and commit the backend was built from (`signalhub`), Java and the OS. See [Version](architecture.md#version). |
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
    "lastEventAt": null,
    "keys": [
      {"id": "b49cd36a-84ed-4581-b4bb-9b89f170a57c", "createdAt": "2026-09-25T16:34:40.417295Z", "revokedAt": null}
    ]
  },
  "keyId": "b49cd36a-84ed-4581-b4bb-9b89f170a57c",
  "apiKey": "shpk1_b49cd36a84ed4581b4bb9b89f170a57c_<secret>"
}
```

Give `apiKey` to the producer through its own secret store, never through the
repository. `lastEventAt` is when SignalHub received the producer's newest
event still stored (`null` before its first one). The
[admin page](architecture.md#the-admin-page) at `http://localhost:8080/admin/#producers`
does all of this in a browser; with curl, manage it (`$PRODUCER` and `$KEY`
are the IDs above):

```sh
H="Authorization: Bearer $ADMIN_TOKEN"
API=http://localhost:8080/api/v1/admin/producers
curl -s "$API" -H "$H"                                     # list producers and key records ({"items": [...]})
curl -s "$API/$PRODUCER" -H "$H"                           # one producer
curl -s -X POST "$API/$PRODUCER/keys" -H "$H"              # issue another key (rotation, step 1)
curl -s -X POST "$API/$PRODUCER/keys/$KEY/revoke" -H "$H"  # revoke the old key (rotation, step 2)
curl -s -X POST "$API/$PRODUCER/disable" -H "$H"           # block all its keys
curl -s -X POST "$API/$PRODUCER/enable" -H "$H"            # unblock its unrevoked keys
```

To check that pushes arrive, and that the devices' preferences filter a
producer as expected, send a [test event](architecture.md#test-events) as the
producer with the admin token, without its key. The body is a producer's own;
the event is stored and pushed as the producer's (`409` if it is disabled):

```sh
curl -s "$API/$PRODUCER/events" -H "$H" -H 'Content-Type: application/json' \
  -d '{"category": "ACTION_REQUIRED", "severity": "HIGH", "title": "Test event"}'   # 201, the event
```

### Clients

Clients (app installations of a user) and their keys are described in
[architecture.md](architecture.md#clients). Register one with the admin
token, for a user (see [Users](#users); without `userId` it is the owner's, the
oldest admin who is not revoked); the response contains its client key, **shown
only this once**:

```sh
curl -s http://localhost:8080/api/v1/admin/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name": "Pixel 8"}'   # or {"name": "Pixel 8", "userId": "<a user's ID>"}
```

```json
{
  "client": {
    "id": "01a0da2c-1f3e-7a51-8d0c-6b1f2e3d4c5b",
    "name": "Pixel 8",
    "admin": true,
    "user": {"id": "01a0da2b-0000-7000-8000-000000000001", "name": "Owner", "role": "ADMIN"},
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

The operator lists, inspects, renames, revokes and deletes clients, paired ones included (`$CLIENT` is the ID above). The
[admin page](architecture.md#the-admin-page) at `http://localhost:8080/admin/`
does all of it in a browser; from a terminal:

```sh
H="Authorization: Bearer $ADMIN_TOKEN"
J='Content-Type: application/json'
API=http://localhost:8080/api/v1/admin/clients
curl -s "$API" -H "$H"                          # all clients ({"items": [...]})
curl -s "$API/$CLIENT" -H "$H"                  # one client
curl -s -X PATCH "$API/$CLIENT" -H "$H" -H "$J" -d '{"name": "Anna'"'"'s phone"}'   # rename it
curl -s -X POST "$API/$CLIENT/revoke" -H "$H"   # revoke it and drop its push target
curl -s -X DELETE "$API/$CLIENT" -H "$H" -w '%{http_code}\n'   # delete it once revoked: 204
```

A revoked client cannot be renamed or changed (`409`); it can only be
deleted, and an active one cannot be deleted (`409`). Events stay. See
[Admin devices](architecture.md#admin-devices) and
[Deleting a revoked client](architecture.md#deleting-a-revoked-client).

A device does part of this with its own client key, through the proxy too,
as its user's role allows ($ADMIN_KEY is an admin device's key): a basic user's
key gets `403`, a mod manages their own devices, an admin those of users who
are not admins, and nothing can be done to an admin's device (`409` on revoke;
see [Device management from a
device](architecture.md#device-management-from-a-device)):

```sh
D=http://localhost:8080/api/v1/client/devices
curl -s "$D" -H "Authorization: Bearer $ADMIN_KEY"                           # every device (an admin's view)
curl -s -X POST "$D/$CLIENT/revoke" -H "Authorization: Bearer $ADMIN_KEY"    # revoke one
curl -s -X DELETE "$D/$CLIENT" -H "Authorization: Bearer $ADMIN_KEY"         # delete a revoked one
```

It also creates pairing codes, for its own user, or for another if it is an
admin (see [Pairing from a
device](architecture.md#pairing-from-a-device)):

```sh
curl -s http://localhost:8080/api/v1/client/pairings \
  -H "Authorization: Bearer $ADMIN_KEY" -H 'Content-Type: application/json' \
  -d '{"name": "Tablet"}' | jq -r .uri   # add "userId" to pair for another user
```

#### Users

Users, their roles, producers' visibility and subscriptions are in
[architecture.md](architecture.md#users-roles-and-subscriptions). The
[admin page](architecture.md#the-admin-page)'s *Users* section does all of it
in a browser; from a terminal, with the admin token:

```sh
H="Authorization: Bearer $ADMIN_TOKEN"
J='Content-Type: application/json'
U=http://localhost:8080/api/v1/admin/users
curl -s "$U" -H "$H" | jq '.items[] | {id, name, role}'              # the users, "Owner" first
USER=$(curl -s "$U" -H "$H" -H "$J" -d '{"name": "Anna", "role": "BASIC"}' | jq -r .id)   # invite
curl -s -X PATCH "$U/$USER" -H "$H" -H "$J" -d '{"role": "MOD"}'     # set the role (ADMIN too: only here)
curl -s http://localhost:8080/api/v1/admin/pairings -H "$H" -H "$J" \
  -d "{\"name\": \"Anna's phone\", \"userId\": \"$USER\"}" | jq -r .uri   # her pairing code
# a private producer of hers, and a public one the others may subscribe to
curl -s http://localhost:8080/api/v1/admin/producers -H "$H" -H "$J" \
  -d "{\"name\": \"annas-script\", \"ownerId\": \"$USER\"}"
curl -s -X PATCH http://localhost:8080/api/v1/admin/producers/$PRODUCER -H "$H" -H "$J" \
  -d '{"visibility": "PUBLIC"}'
curl -s -X PUT "$U/$USER/subscriptions/$PRODUCER" -H "$H"            # subscribe her to it
curl -s -X POST "$U/$USER/revoke" -H "$H"                            # remove her: devices revoked, producers disabled
```

Both reads show each client's latest push results in `pushStatus` (see
[Client API](architecture.md#client-api)), which answers why a device got no
push:

```sh
curl -s "$API/$CLIENT" -H "$H" | jq .pushStatus
```

```json
{
  "lastSuccess": {"at": "2026-09-27T10:00:02.123456Z", "eventId": "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b"},
  "lastFailure": null,
  "pendingRetries": 0
}
```

Every published event that the client's
[push preferences](architecture.md#push-preferences) allow is then pushed to
the target (see [Push dispatch](architecture.md#push-dispatch)); every event
stays in the inbox either way. The client app does all of
this itself; see [Client](#client).

#### Pairing a device

Instead of handing a device its client key, the operator can create a
one-time pairing code, valid for 10 minutes, and the device registers itself
with it (see [Pairing](architecture.md#pairing)). The
[admin page](architecture.md#the-admin-page) at
`http://localhost:8080/admin/` does it in a browser: enter the admin token,
then under **Connect a device** a device name and the user it is for (an admin
user's device is an admin device), and it shows the QR code with a countdown, and copies it as an
image or a link, or downloads it. Once a device has used the code, the page
says which device connected, hides the code and is ready for the next one.
From a terminal:

```sh
curl -s http://localhost:8080/api/v1/admin/pairings \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"name": "Pixel 8"}'   # add "userId" to pair for a user other than the owner
```

```json
{
  "id": "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b",
  "name": "Pixel 8",
  "admin": true,
  "user": {"id": "01a0da2b-0000-7000-8000-000000000001", "name": "Owner", "role": "ADMIN"},
  "code": "shpc1_<secret>",
  "expiresAt": "2026-09-27T10:12:00.123456Z",
  "uri": "signalhub://pair?server=https%3A%2F%2Fsignalhub.example.com&code=shpc1_<secret>"
}
```

`uri` carries `SIGNALHUB_PUBLIC_URL` (see [Configuration](#configuration)) and
is `null` without it. Show it as a QR code in the terminal with
[`qrencode`](https://fukuchi.org/works/qrencode/) (package `qrencode` on
Debian and Ubuntu):

```sh
qrencode -t ansiutf8 "$URI"
```

The app redeems it when the owner scans the QR code or pastes the URI (see
[client/README.md](../client/README.md#set-it-up)). Any other client
redeems the code once, with no body, through the proxy like any client
request, and gets its client and key as registering a client returns them:

```sh
curl -s -X POST https://signalhub.example.com/api/v1/pairing \
  -H "Authorization: Bearer $PAIRING_CODE"
```

A used, expired or unknown code gets `401`. Once a code is redeemed, every
other client of the user and of the admins with a push target that has not
paused pushes gets the [pairing notice](architecture.md#pairing-notice), "New device paired".

Whether the code was used, and by which device, is asked with the pairing's
`id` (see [Whether a code was used](architecture.md#whether-a-code-was-used));
a mod's or an admin's device asks about its own codes the same way at
`/api/v1/client/pairings/$PAIRING_ID` with its key:

```sh
curl -s "http://localhost:8080/api/v1/admin/pairings/$PAIRING_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq '{state, client}'
```

`state` is `PENDING`, `REDEEMED` (with `client`, the new device's ID and
name) or `EXPIRED`; a pairing is `404` once it is deleted, 10 minutes after
it expired.

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
        "link": "https://ci.example.com/runs/1842",
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
  "link": "https://ci.example.com/runs/1842",
  "occurredAt": "2026-09-25T12:03:00Z",
  "createdAt": "2026-09-25T15:31:42.209368Z"
}
```

To retry safely after a timeout, send an `Idempotency-Key` that names the
event (see [architecture.md](architecture.md#idempotent-publishing)). The
first request answers `201`; the same event with the same key again answers
`200` with the stored event and stores nothing, and a different event with
that key `422`:

```sh
curl -si http://localhost:8080/api/v1/events \
  -H "Authorization: Bearer $API_KEY" \
  -H 'Idempotency-Key: nightly-1842-1' \
  -H 'Content-Type: application/json' \
  -d '{"category": "BLOCKED", "severity": "HIGH", "title": "Nightly build failed"}' | head -1
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

The operator deletes test or unwanted events with the admin token (see
[architecture.md](architecture.md#deleting-events)): one event, a selection,
every event of a producer, every event received before a time, or a producer's
events before a time. A dry run answers how many would go and deletes none;
there is no undo:

```sh
A="Authorization: Bearer $ADMIN_TOKEN"
curl -s -X DELETE "http://localhost:8080/api/v1/admin/events/$EVENT" -H "$A" -o /dev/null -w '%{http_code}\n'   # 204
curl -s http://localhost:8080/api/v1/admin/events/delete -H "$A" -H 'Content-Type: application/json' \
  -d "{\"producerId\": \"$PRODUCER\", \"dryRun\": true}"                  # {"count": 12, "dryRun": true}
curl -s http://localhost:8080/api/v1/admin/events/delete -H "$A" -H 'Content-Type: application/json' \
  -d '{"createdBefore": "2026-09-01T00:00:00Z"}'                         # {"count": 40, "dryRun": false}
curl -s http://localhost:8080/api/v1/admin/events/delete -H "$A" -H 'Content-Type: application/json' \
  -d "{\"ids\": [\"$EVENT\", \"$OTHER_EVENT\"]}"                          # {"count": 1, ...}: one was gone
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
| `SIGNALHUB_ADMIN_TOKEN` | Enables the management API for producers, clients and deleting events, and lets the operator list events. At least 32 characters (`openssl rand -hex 32`); shorter stops startup. Unset or empty disables the management API; clients keep reading events with their keys. |
| `SIGNALHUB_EVENTS_RETENTION` | How long events are kept, a duration of at least `1d` such as `365d`; older events are deleted every hour. Shorter stops startup. Unset or empty keeps events forever (the default). See [Retention](architecture.md#retention). |
| `SIGNALHUB_PUBLIC_URL` | The address devices reach SignalHub at, such as `https://signalhub.example.com`; [pairing](architecture.md#pairing) URIs carry it. An absolute `http` or `https` URL without credentials, query or fragment, or startup stops. Unset or empty: pairings have no URI. Compose defaults it to `https://` and `SIGNALHUB_DOMAIN` when that is set. |
| `SIGNALHUB_LOG_JSON` | `true` writes console logs as JSON, one object per line, for log collectors; default `false` (plain text). See [Logs](architecture.md#logs). |
| `SIGNALHUB_PUSH_DISPATCH_INTERVAL` | How often the push dispatcher looks for new events to push; default `2s`. See [Push dispatch](architecture.md#push-dispatch). |
| `SIGNALHUB_PUSH_FCM_CLIENT_OPTIONS_FILE` | Path to the app's Firebase options (JSON, the `firebase-options.json` of [client/README.md](../client/README.md#push-notifications)), served to clients at `GET /api/v1/client/push-config`. Needs `SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE`; an unreadable or invalid file, or a service account key, stops startup. Unset or empty: no options are served. See [Firebase Cloud Messaging](#firebase-cloud-messaging). |
| `SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE` | Path to a Firebase service account key file (JSON). Enables push through Firebase Cloud Messaging (provider `fcm`); an unreadable or invalid file stops startup. Unset or empty: no `fcm` provider, and `fcm` push targets are reported as unsupported. See [Firebase Cloud Messaging](#firebase-cloud-messaging). |

Compose passes `SIGNALHUB_ADMIN_TOKEN`, `SIGNALHUB_EVENTS_RETENTION`,
`SIGNALHUB_LOG_JSON`, `SIGNALHUB_PUBLIC_URL` and the database settings from `.env` (see
`.env.example`); any other variable, such as
`SIGNALHUB_PUSH_DISPATCH_INTERVAL` or a log level, goes in the backend's
`environment` in `compose.override.yaml`, as for FCM below. Never commit
`.env`.
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

To let apps get the Firebase options from the server instead of having them
built in, also mount the app's `firebase-options.json` (see
[client/README.md](../client/README.md#push-notifications)); it holds only
client identifiers, never the service account key:

```yaml
services:
  backend:
    environment:
      SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE: /run/secrets/fcm.json
      SIGNALHUB_PUSH_FCM_CLIENT_OPTIONS_FILE: /run/config/firebase-options.json
    volumes:
      - /path/outside/the/repo/fcm-service-account.json:/run/secrets/fcm.json:ro
      - /path/outside/the/repo/firebase-options.json:/run/config/firebase-options.json:ro
```

The log then shows `Push client options: served for fcm`, and a client key
reads them:

```sh
curl -H "Authorization: Bearer $CLIENT_KEY" http://localhost:8080/api/v1/client/push-config
# {"provider":"fcm","options":{"FIREBASE_PROJECT_ID":"...", ...}}
```

An app built without its own options (no `--dart-define-from-file`) then
sets up push with these after setup (see
[client/README.md](../client/README.md#push-notifications)).

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
shellcheck icon/render.sh                     # the app icon's render script (see client/README.md)
python3 sounds/generate.py --check            # the alert sounds are what their generator makes (client/sounds/)
flutter test                                  # unit and widget tests
flutter build apk --debug                     # Android build (CI builds the release APK instead, below)
flutter build ios --debug --no-codesign       # iOS build (macOS only)
```

The tests need no device, network or credentials: `SignalHubApi` runs
against `FakeBackend`, an in-memory stand-in for the client API built on the
`http` package's `MockClient`, and push against `FakePushService`. They cover
the API client (paths, bearer key, cursors, reading one event, push-target
bodies, push-preference bodies, error mapping), the models (every documented field, unknown enum
values, contract violations), server address and key validation, the app
controller (setup, restart, revoked key, unreachable server, push
permission, token refresh, pushes and returning to the foreground
re-reading the inbox, paging and its
failures, opening a tapped notification's event, disconnect), the Firebase
options from build-time values, and the screens in widget tests (inbox,
paging while scrolling, event details, opening from a notification, the
Settings screen: the gear icon, each group folded and unfolded, their
summaries, the groups left open kept on the device, greyed groups while
push is off, the Devices row only on an admin device, disconnecting after
a confirmation) and
read state (the API calls, the unread count, marking read on opening,
marking unread, marking all read up to the newest event shown, and their
failures), and push preferences (saving each change, what the server
stored, muted producers without inbox events, failures, a server without
them), and the alert settings against `FakeAlertPlatform`, which stands in
for the Android side (what is given to the platform for each sound, volume
and vibration step, pattern and length, and the bundled defaults; saving, restoring after a
restart, previews, a phone keeping them quiet, failures), and the critical events'
settings (what a critical push plays with the switch on and off, reading
them back, the defaults next to a general alert saved before them, and a
pattern and length at their defaults next to settings saved before them),
and which pushes sound on silent and during do-not-disturb (for each
option, a normal and a critical push with and without a different alert,
on silent, on vibrate and during do-not-disturb with and without access,
as `playedOnPhone` in the test fakes models `AlertPlayer`; the carry-over
of the critical-only switches an earlier version saved; previews; access
not given, given later or taken away), and the *Critical alert* sub-group
inside *Alert* (greyed and closed while the switch is off, unfolding and
remembered while it is on). Builds without
Firebase options run without push. The Android code that plays the alert
is compiled by the release APK build and checked on a phone by the device
review.

### Device review

A functional review of the app on a real Android phone is scripted in
[`scripts/device-review/`](../scripts/device-review/README.md): over `adb`,
against the local Compose stack with FCM, it publishes events and checks
start-up, pushes in the foreground, the background and to a killed app,
read state, push preferences, the app's own alert (played with the chosen
sound, and quiet for other apps and during do-not-disturb) and critical
events' (their own alert once switched on, sounding on silent, every push
sounding on silent with *All pushes*, quiet during do-not-disturb), idempotent
publishing, a stopped and a
restarted backend, a phone that was offline, and the backend log. It never
touches the screen unless SignalHub (or the notification shade it opened)
is in front. It is run by hand, with a debug build set up with a client
key, and publishes events (see [Clearing local test data](#clearing-local-test-data)).
CI runs only its unit tests, which need no device:

```sh
python -m unittest discover --start-directory scripts/device-review --verbose
```

## Python SDK

The producer package and `signalhub` command live in `sdk/python/`. See
[architecture.md](architecture.md#producer-sdk-and-cli) for its design and
[`sdk/python/README.md`](../sdk/python/README.md) for installing and using it.
It needs Python 3.10 or later and has no dependencies beyond the standard
library, so there is no lock file; the build backend is pinned in
`sdk/python/pyproject.toml`. Its version there, `0.0.0.dev0`, is a
development placeholder: an install from the repository reports
`SignalHub development build`, and only the release's build carries a
release version (see [Release process](#release-process)). To build the
files a release attaches, with a version of your choice (needs `build`, from
`.github/tools/requirements.txt`, and network access):

```sh
python scripts/release/sdk_files.py 0.0.0+ci /tmp/sdk
```

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
pip install --requirement .github/tools/requirements.txt   # ruff and build
ruff check .
ruff format --check .
python -m unittest discover --start-directory scripts/release --verbose
python -m unittest discover --start-directory scripts/device-review --verbose
# Python SDK, also run with python3.10 in CI
pip install ./sdk/python && signalhub send --help
python -m unittest discover --start-directory sdk/python/tests --top-level-directory sdk/python --verbose
python scripts/release/sdk_files.py 0.0.0+ci "$(mktemp -d)"   # the SDK's release files (needs network)
# Integration examples (need the SDK, curl and jq) and the release's image scripts
shellcheck examples/*/*.sh scripts/release/*.sh
python -m unittest discover --start-directory examples/tests --verbose
# Lints GitHub Actions workflows and the example workflow (needs Docker):
docker build --quiet --tag actionlint .github/tools/actionlint
docker run --rm --volume "$PWD:/repo" --workdir /repo actionlint -color .github/workflows/*.yml examples/github-actions/*.yml

# Client (in client/, needs Flutter; the iOS build needs macOS)
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed .
flutter analyze
shellcheck icon/render.sh
python3 sounds/generate.py --check
flutter test
# The release's APK and its checks, as CI does (needs the Android SDK and a
# key in ANDROID_RELEASE_KEYSTORE and the other variables of app_files.py;
# run from the repository's root):
#   python3 scripts/release/app_files.py 0.0.0-ci "$(git rev-parse HEAD)" "$(mktemp -d)"
flutter build ios --debug --no-codesign

# Backend (needs Docker)
(cd backend && ./mvnw verify)
# The release's image build and its checks (the "Backend image (release build)"
# jobs, on x86-64 and natively on ARM64; needs Docker, jq and curl):
scripts/release/build-image.sh 0.0.0-ci "$(git rev-parse HEAD)" load
scripts/release/check-image.sh signalhub-backend:check 0.0.0-ci "$(git rev-parse HEAD)"
# Container smoke test: the "Backend container" jobs in .github/workflows/ci.yml,
# on x86-64 and natively on ARM64, check that the images match the runner's
# architecture and start the stack with `docker compose up --build --wait` and a random admin
# token, the resource limits of architecture.md#resources and the TLS proxy (with Caddy's own CA), checks liveness, readiness, OpenAPI and metrics, that the image built from source reports a development version, registers a producer, checks
# that publishing without a valid key gets 401, publishes an event with the key
# and reads it back after restarting the backend, lists it with the admin
# token (and expects 401 without it), lists it over HTTPS through the proxy
# and expects 404 there for management, health, metrics and OpenAPI, however
# the path is spelled, and a redirect from plain HTTP, registers a client that lists the event
# with its key, marks it read and counts no unread events, sets a push
# target, expects 409 when deleting it while active, revokes the client and expects 401,
# deletes it (204, then 404) with the event it read kept read, creates a pairing on the host
# (and expects 404 for that through the proxy), checks that its URI names the
# proxy's address, redeems it through the proxy, reads the new client with its
# key, and expects 401 when redeeming it again, sees on the host that the
# pairing was used and by which device, has an admin device pair another device
# and see its own code used through the proxy (403 for another device, 404 for
# the operator's code), revoke the first and delete it (204, then 404) through
# the proxy, publishes with the Python command
# and reads the event back (and expects exit status 1 with an invalid key),
# restarts the backend with JSON logs and checks that every line is JSON, that
# the startup summary is logged, and that no secret is, backs up the database,
# restores it into an empty one and checks that events from before the backup
# (and only those) are back, the producer key still works and the proxy kept
# its CA, and that restoring over existing data fails, runs the integration
# examples as five new producers (the GitHub Actions step twice for one run
# attempt, as a retry would) and lists their events, one each, revokes the producer
# key and expects 401, stops PostgreSQL and expects readiness 503, and checks that the image refuses to start without database
# settings. The "Backend container (upgrade from the latest release)" job starts
# the latest release (from its deployment files if it has them, otherwise from
# its tag with its published image if it has one, or built) with a producer, a
# client and a read event, backs up, upgrades in place to deployment files of
# the commit under test that name the image CI built for it, as in
# docs/deployment.md#upgrades, checks that nothing was built, the data, keys,
# migrations and health, and rolls back by restoring the backup with the
# release. The "Backend container (upgrade from v0.13.0)" job does the same
# from v0.13.0, the oldest release upgrades are tested from, skipping every
# release since. The "End-to-end (producer to push and client inbox)"
# job starts the stack with FCM push enabled through a throwaway service account
# key and scripts/e2e/fake_fcm.py (a stand-in for Google's token endpoint and
# the FCM HTTP v1 API, on the runner), registers a producer and two clients,
# publishes a low and a high severity event with the Python command, checks
# that the client whose preferences want only HIGH gets exactly one FCM message
# with the event's ID, that FCM's UNREGISTERED answer removes the other client's
# push target, and the delivery metrics, then opens the pushed event with the
# client key, lists both events in the inbox and marks the pushed one read.
# The "Deployment (fresh install from docs/deployment.md)" job follows
# docs/deployment.md#setup on a clean runner, from deployment files (checked
# against their SHA256SUMS) that name the image CI built for the commit, so
# nothing is built on the host: .env from the example with mode
# 600 and generated secrets, the proxy with Caddy's own CA for a name that
# resolves to the runner, a throwaway FCM key mounted with the permissions of
# docs/deployment.md#secrets and the resource limits, then checks that no
# secret is logged, that only the documented ports are published, that other
# machines get 401 over TLS, that a producer publishes with the Python command
# and a client reads its inbox through the proxy, that the stack started again
# without the admin token has no management API while the client keeps reading,
# and that every service comes back by itself after `systemctl restart docker`,
# as after a reboot, with the event still there.
```

Each new component adds its own build, lint, and test commands to CI and to
this section in the PR that introduces it.

## Dependency updates

Every dependency and tool version is pinned, and Dependabot
(`.github/dependabot.yml`) proposes updates weekly as PRs with Conventional
Commit titles, which go through CI like any other:

| What | Where it is pinned | Dependabot ecosystem |
|---|---|---|
| GitHub Actions | `.github/workflows/*.yml` | `github-actions` |
| Backend libraries and Maven plugins | `backend/pom.xml` | `maven` |
| Backend build and runtime images | `backend/Dockerfile` | `docker` |
| PostgreSQL and Caddy images | `compose.yaml` | `docker-compose` |
| Client packages | `client/pubspec.yaml`, `client/pubspec.lock` | `pub` |
| The SDK's build backend (setuptools) | `sdk/python/pyproject.toml` | `pip` |
| ruff and build (the SDK's release files) | `.github/tools/requirements.txt` | `pip` |
| actionlint (and its shellcheck) | `.github/tools/actionlint/Dockerfile` | `docker` |

Two versions have to follow others by hand:

- **The tests' PostgreSQL image.** Dev Services
  (`application.properties`) and the Testcontainers tests use the tag of the
  Compose image, so tests run on the PostgreSQL that is deployed. Dependabot
  updates only `compose.yaml`; a first step of the `Backend (build + test)`
  job fails while any of them differs, so a PR changing the Compose tag has
  to change the others too. A new major version is also an operator change
  (a dump and restore, see
  [deployment.md](deployment.md#a-new-postgresql-major-version)), never a routine
  update.
- **Flutter.** No Dependabot ecosystem updates the Flutter SDK.
  `FLUTTER_VERSION` in `.github/workflows/ci.yml` and
  `.github/workflows/release.yml` (a test in `scripts/release` fails while
  they differ) and the version under [Client](#client) are raised together
  by hand, from the stable releases;
  the packages in `client/pubspec.lock` are tracked by `pub`.

The backend's Java version follows LTS releases only (Java 25 since R25). A
Dependabot PR moving the images of `backend/Dockerfile` to another Java major
version is not a routine update: a new Java version changes
`maven.compiler.release`, CI's JDK and the documentation together, in its
own PR.

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
  release)`, `Backend container (upgrade from v0.13.0)`, `End-to-end (producer to push and client inbox)`, `Deployment (fresh
  install from docs/deployment.md)`, `Client (analyze + test +
  Android build)`, `Client (iOS build)`, and `Conventional Commit title`.
  Require branches to be up to date before merging.
- Actions workflow permissions must allow `contents: write` for the release
  job (it requests this explicitly).
- The Android release key (decision D6) in four repository secrets
  (*Settings → Secrets and variables → Actions*), which only the release
  workflow's `app` job reads: `ANDROID_RELEASE_KEYSTORE_BASE64` (the
  keystore file, base64), `ANDROID_RELEASE_KEYSTORE_PASSWORD`,
  `ANDROID_RELEASE_KEY_ALIAS` and `ANDROID_RELEASE_KEY_PASSWORD`. They are
  the maintainer's; the keystore is never committed, and its offline backup
  is the only way to replace them. Losing the key means official installs
  can no longer be updated (see
  [client/README.md](../client/README.md#signing)).
