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

To register producers in dev mode, enable the management API with an admin
token (see [Producers and API keys](#producers-and-api-keys)):

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
with the database up and after it stops, Flyway startup migration, the
production configuration, the OpenAPI document, and the events API: the HTTP
contract and validation (`EventApiTest`), and what reaches PostgreSQL,
including the schema's own constraints (`EventPersistenceTest`). Producer
authentication is covered by `EventAuthenticationTest` (every way publishing
can be rejected, rotation, revocation, disabling, and that the payload cannot
claim a producer), `ProducerAdminApiTest` and `AdminApiDisabledTest` (the
management API and its admin-token guard), `ProducerPersistenceTest` (only
hashes are stored), `ProducerMigrationTest` (upgrading a database that holds
events from before authentication), and unit tests for the key format, bearer
parsing and admin token (`ApiKeysTest`, `BearerTokenTest`, `AdminTokenTest`).
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
startup. Hibernate never creates or alters tables. There is no separate migrate
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

### Endpoints

| Path | Purpose |
|---|---|
| `/api/v1/events` | `POST`: publish an event, with a producer API key. See [Events API](#events-api). |
| `/api/v1/events/{id}` | `GET`: read an event by its ID. |
| `/api/v1/admin/producers/...` | Producer management, with the admin token. See [Producers and API keys](#producers-and-api-keys). |
| `/q/health/live` | Liveness: 200 while the process runs. No dependency checks. |
| `/q/health/ready` | Readiness: 200 when PostgreSQL is reachable, 503 otherwise. |
| `/q/health` | Both of the above combined. |
| `/q/openapi` | OpenAPI document (YAML; `?format=json` for JSON). |
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

Read it back, including after restarting the service:

```sh
curl http://localhost:8080/api/v1/events/01a0d931-9c33-7989-a9ea-adb6724470e6
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
| `SIGNALHUB_ADMIN_TOKEN` | Enables the producer management API. At least 32 characters (`openssl rand -hex 32`); shorter stops startup. Unset or empty disables it. |

Compose derives them from `.env` (see `.env.example`). Never commit `.env`.

## Local validation

CI runs:

```sh
# Repository tooling
pip install ruff==0.16.9
ruff check .
ruff format --check .
python -m unittest discover --start-directory scripts/release --verbose
# Lints GitHub Actions workflows (needs Docker):
docker run --rm --volume "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color

# Backend (needs Docker)
(cd backend && ./mvnw verify)
# Container smoke test: the "Backend container" job in .github/workflows/ci.yml
# starts the stack with `docker compose up --build --wait` and a random admin
# token, checks liveness, readiness and OpenAPI, registers a producer, checks
# that publishing without a valid key gets 401, publishes an event with the key
# and reads it back after restarting the backend, revokes the key and expects
# 401, stops PostgreSQL and expects readiness 503, and checks that the image
# refuses to start without database settings.
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
  `Backend container (Compose smoke test)`, and `Conventional Commit title`.
  Require branches to be up to date before merging.
- Actions workflow permissions must allow `contents: write` for the release
  job (it requests this explicitly).
