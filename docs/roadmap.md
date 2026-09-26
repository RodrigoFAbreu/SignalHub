# SignalHub Roadmap

Status: Active  
Development model: lightweight trunk-based development  
Release model: every merge to `main` is releasable and produces a release  
Backend: Java 21 + Quarkus + PostgreSQL  
Client strategy: cross-platform capable; final mobile technology is intentionally not fixed yet

## 1. Product goal

SignalHub is a producer-agnostic personal notification and event platform.

Any system should be able to publish an event through a stable HTTP contract without SignalHub containing special-case knowledge about that producer.

Examples of future producers include:

- autonomous coding agents and orchestrators
- CI/CD systems
- Workflow Controller / Workflow Manager
- usage-limit monitors
- homelab and Raspberry Pi monitoring
- scheduled jobs
- scripts and developer tooling
- future applications unrelated to the current development workflow

SignalHub should persist those events, route them to registered clients, notify the user, and provide a useful history/inbox.

Core SignalHub code must not contain producer-specific semantics. Producer-specific information belongs in generic metadata or integration code at the edge of the system.

---

## 2. Development and release rules

`main` is always releasable.

All development follows these rules:

1. Start each increment from the latest `main`.
2. Use a short-lived branch.
3. Implement one bounded, coherent, independently releasable increment.
4. Run all applicable validation.
5. Open a pull request against `main`.
6. Required CI must be green before merge.
7. Pull requests are squash merged.
8. The squash commit title follows Conventional Commit semantics.
9. Every merge to `main` produces a release.
10. Never knowingly merge broken, partial, or placeholder-only work.
11. Never push implementation work directly to `main`.
12. Do not stack a new roadmap increment on an unmerged implementation PR.

### Automated progression

When repository policy enables automatic merging:

- an implementation PR may enable GitHub auto-merge only after all required validation and review gates are configured;
- GitHub, not an ad-hoc force merge, performs the merge once branch protection requirements are satisfied;
- the next roadmap increment starts only after the previous PR is actually merged and its release workflow is verified;
- failed CI must be fixed on the same feature branch before merge;
- a failed release caused by repository or implementation defects blocks new feature work until corrected.

The orchestrator must stop instead of auto-merging when a milestone introduces a genuine product or architecture decision not already settled by this roadmap or normative repository documentation.

---

## 3. Completed foundations

The following capabilities are already implemented and merged unless repository state says otherwise.

### R0 - Repository and release foundation

- repository development rules
- `CLAUDE.md`
- architecture/development documentation
- GitHub Actions validation
- Conventional Commit release semantics
- automatic releases from `main`
- lightweight trunk-based development

### R1 - Backend architecture

- Java 21
- Quarkus
- PostgreSQL
- Hibernate ORM / Panache
- Flyway
- Jakarta Validation
- SmallRye OpenAPI
- SmallRye Health
- Maven
- Docker / Docker Compose
- JUnit / RestAssured
- formatting and static analysis

### R2 - Backend runtime foundation

- runnable Quarkus backend
- PostgreSQL connectivity
- Flyway-managed schema
- liveness and database-backed readiness
- OpenAPI
- Docker image
- Compose stack
- CI integration

### R3 - Generic event ingestion

- persisted generic event model
- `POST /api/v1/events`
- `GET /api/v1/events/{id}`
- generic category and severity semantics
- server-generated canonical event identity/time
- arbitrary bounded JSON metadata
- strict API validation
- PostgreSQL persistence

### R4 - Producer authentication

- persistent producer identity
- producer API-key authentication
- secure key storage/verification
- producer revocation/disable capability
- key rotation/revocation lifecycle
- event identity bound to authenticated producer
- authenticated ingestion

### R5 - Event inbox/query API

- `GET /api/v1/events`: events newest first (`createdAt`, then `id`)
- cursor (keyset) pagination with opaque, versioned cursors; `limit` 1-100
- filters: producer, category, severity (each repeatable), `createdAt` range
- per-parameter `400` validation errors
- listing guarded by the admin token, the owner's credential until
  owner/client authentication exists (R6); disabled (`404`) without one
- `(created_at, id)` and `(producer_id, created_at, id)` indexes (V3)
- tests against real PostgreSQL, OpenAPI, Compose smoke test, docs

### R6 - Client/device registration

- `clients` table (V4): one row per client installation, server-generated
  UUIDv7 identity, owner-chosen label
- per-client keys (`shck1_<client id>_<secret>`), hash-only storage, issued by
  the operator through `/api/v1/admin/clients` (register, list, get, revoke)
- client keys read the event listing (the admin token still may); this is the
  client authentication that R5 deferred
- provider-neutral push target (`provider` name + opaque token) managed by the
  client through `/api/v1/client/push-target`; write-only token, one client
  per target, removed on revocation
- no push delivery; tests against real PostgreSQL, OpenAPI, Compose smoke
  test, docs

### R7 - Push-provider abstraction

- `PushProvider` port (`name()`, `send(token, message)`) and provider-neutral
  `PushMessage`; concrete providers are CDI beans at the edge
- classified outcomes: `DELIVERED`, `INVALID_TARGET`, `TRANSIENT_FAILURE`,
  `PERMANENT_FAILURE`
- `PushDelivery.deliver(clientId, message)`: resolves the client's push
  target and provider, sends outside transactions, removes invalid targets
  (unless replaced meanwhile), reports `NO_TARGET` / `UNSUPPORTED_PROVIDER`
- startup check of provider names; test-only fake provider; no retries or
  queues

### R8a - FCM provider

- `fcm` `PushProvider` over the FCM HTTP v1 API, active only when
  `SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE` names a service account key file;
  an invalid file stops startup
- OAuth 2.0 access tokens from the service account (signed JWT, JDK only, no
  Google SDK), cached and renewed before expiry
- FCM answers mapped to outcomes; only `UNREGISTERED` removes a target
- tests against an in-process fake of the token endpoint and FCM API; no
  credentials or network in CI; operator documentation

### R8b - Event-triggered push dispatch

- every stored event is pushed to every client with a push target (no
  filtering until R12)
- `push_dispatches` outbox (V5) written in the event's transaction; a
  scheduled dispatcher claims rows with an expiring lease, sends outside
  transactions, and deletes them: at-least-once, no external queue
- push content from generic fields: title, message shortened to 500
  characters, data `eventId`, `category`, `severity`
- one attempt per client; retries are R13

### R9 - Cross-platform client foundation

- technology: **Flutter** (maintainer decision), one codebase for Android and
  iOS in `client/`; recorded in `docs/architecture.md`
- setup with the server address and a client key, checked with
  `GET /api/v1/client` and kept in platform secure storage
- provider-neutral `PushService` port; Firebase Cloud Messaging adapter at
  the edge (provider `fcm`), configured with the owner's Firebase project at
  build time and never committed; builds without it run without push
- push target set through `PUT /api/v1/client/push-target` on setup, start
  and token refresh; removed on disconnect; revoked keys return to setup
- push reception: system notifications in the background, an in-app list in
  the foreground, deduplicated by event ID; the newest event from the API
- no backend changes; unit and widget tests against fakes; CI analyzes,
  tests and builds Android and iOS
- receiving a push on a real device needs the maintainer's Firebase project
  (and Apple account for iOS); that confirmation also closes R8's exit
  criterion

### R10 - Notification inbox UI

- the app's home screen is the inbox: every event, newest first, 30 per page
  over `GET /api/v1/events`, the next page read with the cursor when
  scrolling near the end; pull to refresh; loading, empty and error states
  with retry
- rows show title, category (icon), severity (color), producer name and
  `createdAt`, from generic fields only
- event detail view with every field, metadata as indented JSON (opaque)
- tapping a notification opens its event (also when it started the app),
  read with `GET /api/v1/events/{id}` if the inbox does not have it; pushes
  received while open re-read the inbox
- device name, server and push status moved to a "This device" screen
- no backend changes; unit and widget tests against fakes

### R11a - Read state API

- one nullable `readAt` per event (V6): read state belongs to the single
  owner, so it is the same on every client
- `PUT` / `DELETE /api/v1/events/{id}/read` mark one event read or unread,
  idempotently, keeping the first read time
- `POST /api/v1/events/read` with `through` marks every unread event up to
  that event (listing order) read; newer events stay unread
- `GET /api/v1/events/unread-count`; `readAt` in every event representation
- all require a client key or the admin token; partial index over unread
  events; tests against real PostgreSQL, OpenAPI, Compose smoke test, docs

### R11b - Read state in the client app

- unread rows have a bold title and a dot; the app bar shows the server's
  unread count, re-read with the inbox (also after a push)
- opening an event, from the inbox or a notification, marks it read; a
  failure leaves it unread until it is opened again
- the event screen marks an event unread again and returns to the inbox
- *Mark all as read* marks read up to the newest event shown; events that
  arrived since stay unread
- no backend changes; unit and widget tests against the fake backend

### R12a - Push preferences API

- per-client push preferences (V7): `enabled` (pause), `minimumSeverity`,
  `mutedCategories`, `mutedProducerIds` (at most 100); defaults push every
  event, so existing clients are unchanged
- `PUT /api/v1/client/push-preferences` replaces them (absent fields take
  their defaults); `pushPreferences` in every client representation
- the dispatcher skips clients whose preferences exclude an event, read at
  dispatch time; events are stored and listed regardless
- generic fields only; no quiet hours (not justified yet); tests against real
  PostgreSQL, OpenAPI, Compose smoke test, docs

### R12b - Push preferences in the client app

- a *Notifications* screen (from the inbox menu) sets this client's push
  preferences: pause, minimum severity, a switch per category and per
  producer
- each change is saved at once with `PUT /api/v1/client/push-preferences`
  (all fields, as the API replaces them); the screen shows what the server
  stored, and a failure leaves it unchanged
- producers offered are those of the events in the inbox (client keys cannot
  list producers); muted producers without inbox events are listed by ID
- severities and categories unknown to the app are kept on change; a server
  without push preferences is reported
- no backend changes; unit and widget tests against the fake backend

### R13 - Delivery reliability

- a send that fails temporarily (`TRANSIENT_FAILURE`) is sent again, up to 5
  sends in all, after 30 s, 2, 10 and 30 minutes; other results are final
  (invalid targets are removed, permanent failures and missing targets are
  not retried)
- `push_retries` rows (V8) per event and client, written in the transaction
  that completes the event's dispatch and claimed with an expiring lease like
  the outbox: retries survive restarts, no external queue
- a retry re-reads the client's push target and preferences
- final failure: the retry is dropped with a warning naming event and
  client; no delivery-attempt records (not justified: the event stays in the
  inbox)
- tests against real PostgreSQL with the fake provider, docs

### R14 - Producer SDK and CLI

- Python package and `signalhub send` command in `sdk/python/`, over the
  public `POST /api/v1/events` only; standard library only, Python 3.10+;
  installed from the repository at a release tag (not on PyPI)
- server address and API key from `SIGNALHUB_URL`, `SIGNALHUB_API_KEY` or
  `SIGNALHUB_API_KEY_FILE` (the command also takes `--url` and
  `--api-key-file`, never the key itself)
- every event field: category and severity case-insensitive and not checked
  locally, metadata as a JSON object and/or `KEY=VALUE` pairs, message from
  standard input, `occurredAt` with an offset
- the server's violations printed; exit status 0 published, 1 rejected,
  2 usage or configuration, 3 temporary failure; no automatic retries
  (publishing is not idempotent yet)
- the event ID printed, or the stored event with `--json`; raw HTTP/curl
  usage documented alongside
- unit tests against an in-process fake HTTP server on Python 3.10 and 3.12;
  the Compose smoke test publishes with the command against the real backend

### R15a - Metrics

- Prometheus metrics at `/q/metrics` (Micrometer): HTTP requests by templated
  path, JVM, process and the database connection pool
- SignalHub meters: events published; pushes by delivery result; retries
  given up; dispatch and retry backlog (counted by each dispatcher run, so
  scrapes never query the database)
- no credentials, IDs, names or event content in meters; unauthenticated like
  health, published on `127.0.0.1` by Compose
- tests against real PostgreSQL with the fake provider; the Compose smoke test
  reads the metrics

### R15b - Structured logs and startup diagnostics

- optional JSON console logs (`SIGNALHUB_LOG_JSON=true`, Quarkus
  `quarkus-logging-json`), one object per line for log collectors; plain text
  stays the default; levels through the standard Quarkus variables
- one `INFO` line at startup with the effective configuration: profile,
  database URL (without parameters or user information) and user, management
  API on or off, FCM credentials file, dispatch interval, log format, Java
  version, CPUs and maximum heap; never a secret value
- configuration errors keep stopping startup with the setting to fix
- tests of the summary and the prod configuration; the Compose smoke test
  restarts the backend with JSON logs and checks every line, the summary, and
  that no secret is logged

### R15c - Event retention

- optional retention period (`SIGNALHUB_EVENTS_RETENTION`, a duration such as
  `365d`, at least one day or startup stops); unset keeps events forever, so
  upgrading never deletes history
- age from the server's `createdAt`; read state, producer, category and
  severity do not matter (no per-category rules: not justified)
- an hourly job deletes expired events oldest first, 1000 per transaction
  through the existing `(created_at, id)` index; pending pushes and retries
  cascade; no migration
- `signalhub_events_deleted_total` counter, an `INFO` line per run that
  deletes, and the period in the startup summary
- tests against real PostgreSQL; the Compose smoke test sets a period and
  checks the summary

### R15d - Backup/restore and resource guidance

- documented backup of the whole database with `pg_dump` (custom format)
  inside the Compose database container, while the backend runs; `.env`
  and the FCM key file are backed up separately
- restore with `pg_restore` into an empty database before the backend
  starts, in one transaction; restoring over existing data fails and
  changes nothing; newer releases migrate a restored schema forward; also
  the way to a new PostgreSQL major version
- resource guidance: 512 MiB and one CPU for the backend, 256 MiB for
  PostgreSQL, set in a `compose.override.yaml`; about 1 KiB per typical
  event (measured), and how to check the database size
- no code changes; the Compose smoke test runs with those limits, backs up,
  restores into an empty database and checks the data, keys and the refusal
  to restore over existing data

### R16a - ARM64 images and a verified ARM64 build

- the backend's build and runtime base images and PostgreSQL's are
  multi-platform (pinned by index digest), so `docker compose up --build`
  builds for the host's architecture, x86-64 or ARM64; no image registry,
  images are built on the host
- the Compose smoke test runs natively on an ARM64 runner as well as on
  x86-64, and checks that the images match the runner's architecture; the
  ARM64 job is named `Backend container (Compose smoke test, ARM64)`

### R16b - TLS reverse proxy, secrets and network exposure

- an optional `proxy` Compose profile (`COMPOSE_PROFILES=proxy` in `.env`)
  runs Caddy (multi-platform image pinned by digest) with `proxy/Caddyfile`:
  TLS for `SIGNALHUB_DOMAIN`, from Let's Encrypt (`SIGNALHUB_TLS` an email
  address) or Caddy's own CA (`internal`); HTTP redirects to HTTPS;
  certificates in a `proxy-data` volume; without both settings it does not
  start
- only `/api/` is forwarded, without the management API (`/api/v1/admin/`);
  health, metrics and OpenAPI stay on the backend's `127.0.0.1` port;
  matched on the normalized path
- `docs/deployment.md`: setup on a home server, certificate choices,
  network exposure and firewall, where each secret lives
- restoring a backup removes only the database volume, so the proxy keeps
  its certificates
- no backend changes; the Compose smoke test (x86-64 and ARM64) runs with
  the proxy and its own CA, reads the inbox over HTTPS, and checks the
  `404`s, however the path is spelled, and the redirect

### R16c - Upgrade procedure and health monitoring

- `docs/deployment.md` documents upgrades: read the release notes, back up,
  check out the new tag, compare `.env.example`, `docker compose up --build
  --wait`, check health; rolling back is restoring the pre-upgrade backup
  with the older release, since migrations only go forward; a new
  PostgreSQL major version is moved with a backup and restore
- health monitoring: what Docker's restart policy and health checks already
  do, readiness checked from the host and the API (`401`) from another
  machine, alerting through a channel that does not depend on SignalHub,
  disk space, delivery metrics and logs
- no backend changes; a new CI job, `Backend container (upgrade from the
  latest release)`, starts the latest release, stores a producer, a client
  and a read event, backs up, upgrades in place to the commit under test,
  checks the data, keys, preferences, every migration and the health of
  every service, then rolls back to the release by restoring the backup
- deferred to R18 (upgrade path review): refusing to start an older release
  on a database a newer one migrated; done in R18a

### R17 - Integration examples

- `examples/`, edge-only producers over the public API, each with its own
  API key and no backend, schema or client changes: a shell wrapper that
  reports a command's outcome (`curl` and `jq`), a homelab disk-usage
  monitor (the `signalhub` command), a GitHub Actions workflow that reports
  failed runs, a coding-agent hook for human gates and completions (Claude
  Code `Notification` and `Stop` hooks, never blocking the agent), and a
  usage-threshold monitor that notifies once per level with a state file
- the API key never on a command line: from standard input for `curl`, or
  the environment or a key file
- tests run every example, including the workflow step's script, against a
  fake events endpoint; shellcheck and actionlint lint them; the Compose
  smoke test runs them against the real backend as four producers

### R18a - Refusing a newer schema

- the backend refuses to start on a database holding a migration it does not
  have (a newer release migrated it), before validating or migrating, so it
  changes nothing; its log names the unknown migrations and points to
  rolling back by restoring a backup (`SchemaVersionGuard`, a Flyway
  callback installed through Quarkus's Flyway configuration customizer)
- releases up to v0.21.0 already refused through Flyway's validation, but
  its message advises `repair`, which would delete the newer migrations from
  the schema history and leave their changes in place; the rollback
  documentation now warns against it
- tested against real PostgreSQL with Flyway validation on and off, and in
  the Compose smoke test, where the packaged image refuses a database with a
  recorded migration it does not have

### R18b - Reading an event needs the owner's credential

- `GET /api/v1/events/{id}` requires a client key or the admin token, like
  the listing and read state; a producer key, another credential or none
  gets the usual `401`, before the event is looked up, so an unauthenticated
  caller never learns whether an ID exists (breaking: releases up to
  v0.22 answered anyone who knew the ID)
- every product API endpoint behind the proxy now requires a credential; the
  app already sends its client key, and the Compose smoke test the admin
  token
- tested against real PostgreSQL (client key, admin token, producer key,
  wrong or missing credential, unknown and malformed IDs), the OpenAPI
  document, the app's fake server and the Compose smoke test

### R18c - One error format

- every error under `/api/` carries the documented
  `{"title", "status", "violations"}` body, including those Quarkus raises
  before a resource runs: an unknown path or malformed ID (`404`), an
  unsupported method (`405`), an unacceptable `Accept` header (`406`) and a
  non-JSON body (`415`), titled by their reason phrase; releases up to v0.23
  answered them without a body
- `413` stays without a body: the HTTP server refuses an oversized body
  before routing; documented as the one exception
- Quarkus's own endpoints under `/q` are unchanged
- tested against real PostgreSQL (`ApiErrorsTest`) and in the OpenAPI
  document

---

## 4. Planned roadmap

Roadmap items are ordered by dependency, but each item may be split into smaller releasable increments if implementation evidence shows that doing so is safer or more reviewable.

### R5 - Event inbox/query API

Status: complete (see section 3).

Goal: provide the read model required by real clients.

Implement:

- paginated event listing
- deterministic ordering
- filtering by appropriate existing generic properties, initially:
  - producer
  - category
  - severity
  - time range
- sensible pagination contract
- stable API response models
- tests against real PostgreSQL
- OpenAPI/documentation

Constraints:

- do not introduce full-text search prematurely
- do not add producer-specific filters
- do not add read/unread state in this milestone unless needed by a separately scoped increment

Exit criteria:

- a client can obtain a paginated chronological SignalHub inbox without knowing event IDs in advance

### R6 - Client/device registration

Status: complete (see section 3).

Goal: establish a generic model for notification-capable client installations.

Implement:

- client/device registration model
- server-generated client/device identity
- platform/provider-neutral core representation
- registration/update/revocation lifecycle
- association needed for future delivery
- secure management semantics appropriate to the current single-user/self-hosted model
- tests, migration, OpenAPI and documentation

Constraints:

- core domain must not become FCM-specific
- no actual push delivery yet
- do not assume Android-only

Exit criteria:

- SignalHub can persist and manage one or more notification-capable client installations without sending notifications

### R7 - Push-provider abstraction

Status: complete (see section 3).

Goal: create a minimal delivery boundary without coupling the domain to one provider.

Implement:

- generic push-delivery interface/port
- provider-neutral delivery request/result representation
- clear provider error classification where currently justified
- configuration boundary for concrete providers
- test fake/stub provider
- no speculative multi-provider framework

Constraints:

- keep abstraction small
- do not add queues/retry workers yet
- no provider-specific fields in core event/domain models

Exit criteria:

- backend domain/application code can request a push delivery without depending directly on FCM/APNs implementation classes

### R8 - FCM delivery

Status: implemented as R8a (the `fcm` provider) and R8b (event-triggered
dispatch); see section 3. Verifying delivery to a real device needs the
maintainer's Firebase project and a client (R9), so the exit criterion is
confirmed together with R9.

Goal: deliver real push notifications to supported mobile clients.

Implement:

- Firebase Cloud Messaging provider
- credential/configuration handling with no secrets committed
- delivery to registered compatible devices
- event-to-notification mapping
- handling of permanently invalid device tokens
- meaningful delivery result persistence only if justified
- local/test substitute so CI does not require real Firebase credentials
- end-to-end documentation

Constraints:

- keep FCM at the infrastructure edge
- do not make the platform Android-only
- APNs/direct iOS support may be a later provider if the selected client technology requires it

Exit criteria:

- publishing an authenticated event can result in a real push notification on a registered test device

### R9 - Cross-platform client foundation

Status: complete (see section 3). Flutter was chosen by the maintainer.

Goal: create the first real user-facing client capable of targeting Android and iOS from one product codebase where practical.

Before implementation, choose the mobile technology based on current project needs and document the decision.

Candidate technologies include:

- Flutter
- Kotlin Multiplatform / Compose Multiplatform
- React Native

Selection criteria:

- Android + iOS support
- maintainability
- push-notification ecosystem
- background notification handling
- developer experience
- testing
- long-term platform support
- no unnecessary backend coupling

Implement the minimal application foundation:

- application shell/navigation
- backend configuration
- secure local handling of any client credentials/tokens
- device registration integration
- push reception
- basic event model mapping
- tests appropriate to the selected platform

Exit criteria:

- one codebase can run on the initially supported mobile platforms and receive SignalHub push notifications

Human gate:

- choosing the cross-platform client technology is an architecture/product decision unless already settled in normative docs. Stop for human confirmation before locking it in.

### R10 - Notification inbox UI

Status: complete (see section 3). Receiving a push on a real device and
opening it still needs the maintainer's Firebase project (see R9).

Goal: make SignalHub useful as a persistent personal notification center.

Implement:

- paginated inbox
- event detail view
- category/severity presentation
- producer/source presentation
- timestamps
- refresh/retry/error states
- deep-link/open-from-push behavior where appropriate

Constraints:

- UI must remain generic and not contain Workflow-specific assumptions

Exit criteria:

- the user can receive a push, open SignalHub, inspect the event, and browse recent history

### R11 - Read/unread state

Status: complete, as R11a (backend read state and API) and R11b (read state
in the app); see section 3.

Goal: support notification lifecycle state across client sessions.

Implement:

- explicit read/unread semantics
- backend persistence if cross-device consistency requires it
- APIs needed by the client
- unread count
- mark-one and sensible bulk behavior
- tests and migrations

Exit criteria:

- inbox can reliably distinguish new/unread events from read events

### R12 - Notification preferences and routing

Status: complete, as R12a (backend push preferences and API) and R12b
(push preferences in the client app); see section 3.

Goal: let the user control what causes an interrupt without preventing events from being persisted.

Implement appropriate generic preferences such as:

- category
- severity
- producer
- push enabled/disabled
- quiet/suppression behavior if justified

Principle:

- persistence/history and push interruption are separate concerns; an event can remain in the inbox even when a push is suppressed

Constraints:

- avoid complex rule engines
- do not add producer-specific policy code

Exit criteria:

- user can reduce unwanted push notifications while retaining event history

### R13 - Delivery reliability

Status: complete (see section 3).

Goal: make push delivery resilient enough for unattended automation.

Evaluate and implement only what current failure modes justify:

- bounded retries
- transient/permanent error distinction
- retry backoff
- delivery attempt state if needed
- idempotency around delivery
- dead-letter/final failure representation if needed

Architecture constraint:

- do not introduce Kafka/RabbitMQ/Redis solely because they are conventional
- prefer the simplest persistent mechanism adequate for expected SignalHub scale
- introduce external queue infrastructure only with measured/clear justification

Exit criteria:

- transient provider failures do not silently lose notifications and permanent failures converge cleanly

### R14 - Producer SDK and CLI

Status: complete (see section 3).

Goal: make integrating arbitrary systems trivial.

Start with a small Python producer package/CLI unless repository evidence justifies another first language.

Capabilities:

- configure SignalHub endpoint
- securely provide API key
- publish event
- ergonomic category/severity handling
- arbitrary metadata
- actionable errors
- shell/CI-friendly output and exit status
- examples

Example eventual usage:

```bash
signalhub send \
  --category ACTION_REQUIRED \
  --severity HIGH \
  --title "Implementation review required" \
  --message "A human gate is waiting."
```

Constraints:

- SDK is a consumer of the public API, not a privileged backend coupling
- keep raw HTTP/curl integration documented as well

Exit criteria:

- integrating a new script or automation requires only endpoint + credential + a simple command/library call

### R15 - Observability and operational hardening

Status: complete, as R15a (metrics), R15b (structured logs and startup
diagnostics), R15c (event retention) and R15d (backup/restore and resource
guidance); see section 3. OpenTelemetry tracing is not justified for a
single service yet.

Goal: make the self-hosted service easy to operate.

Evaluate and implement:

- structured application logs
- useful metrics
- OpenTelemetry where beneficial
- database/runtime metrics
- delivery metrics
- startup/configuration diagnostics
- retention/cleanup policy for historical events
- backup/restore documentation
- container/runtime resource guidance

Exit criteria:

- an operator can understand service health, failures, storage growth and delivery behavior without attaching a debugger

### R16 - Raspberry Pi / self-hosted deployment

Status: complete, as R16a (ARM64 images and a verified ARM64 build), R16b
(TLS reverse proxy, secrets and network exposure) and R16c (upgrade
procedure and health monitoring), see section 3; durable storage, the
restart policy, backup and resource expectations come from R2 and R15d.
Running unattended on a real Raspberry Pi is the maintainer's to confirm;
CI builds and runs the stack natively on ARM64.

Goal: provide a supported practical deployment for a small home server such as Raspberry Pi 5.

Implement/document:

- ARM64-compatible images
- durable PostgreSQL storage
- restart policy
- reverse proxy/TLS architecture
- secrets/configuration strategy
- backup procedure
- upgrade procedure
- health monitoring
- resource expectations
- safe network exposure

Constraints:

- do not expose unauthenticated management surfaces
- TLS should terminate through an appropriate reverse proxy or equivalent
- deployment remains portable beyond Raspberry Pi

Exit criteria:

- SignalHub can run unattended on an ARM64 home server and survive normal restarts/upgrades without data loss

### R17 - Integration examples

Status: complete (see section 3).

Goal: prove producer agnosticism.

Provide small, edge-only examples for multiple unrelated producers, such as:

- GitHub Actions
- generic shell script
- homelab/disk-usage monitor
- coding-agent completion/human-gate notification
- usage-threshold monitor

These are examples/clients only.

Core backend behavior must not change based on producer type.

Exit criteria:

- several unrelated systems can publish useful notifications through the same public contract

### R18 - v1.0 hardening and contract review

Status: in progress; R18a (refusing a newer schema), R18b (reading an
event needs the owner's credential) and R18c (one error format) are complete
(see section 3).

Goal: deliberately declare the first stable SignalHub contract.

Before `v1.0.0`, review:

- public REST API consistency
- authentication/key lifecycle
- event schema
- enum evolution strategy
- pagination
- migrations and upgrade path (refusing to start an older release on a newer schema: done in R18a)
- client/device lifecycle
- push semantics
- error formats (one JSON body for every product API error but `413`: done in R18c)
- configuration compatibility
- backup/restore
- deployment documentation
- security boundaries (reading an event by ID without a credential: closed in R18b)
- observability
- test coverage
- dependency health
- release automation

Perform:

- compatibility review
- cleanup of temporary/pre-1.0 decisions
- removal of obsolete compatibility paths where appropriate
- full end-to-end test from producer -> API -> persistence -> push -> client inbox
- fresh-install deployment test
- upgrade-from-supported-previous-release test

Human gate:

- promotion to `v1.0.0` is always an explicit human decision and must never happen merely because of an automated Conventional Commit version bump.

Exit criteria:

- maintainer explicitly approves the public contract as stable and the repository passes all documented v1.0 readiness checks

---

## 5. Explicit non-goals unless added later

Do not add these merely because they are common infrastructure choices:

- Kafka
- RabbitMQ
- Redis
- Kubernetes
- microservices
- service mesh
- GraphQL
- Elasticsearch
- complex rule engines
- multi-tenant SaaS architecture
- enterprise IAM/Keycloak
- Workflow-specific backend logic
- Claude-specific backend logic

SignalHub should remain a small, understandable service until real requirements justify additional infrastructure.

---

## 6. Orchestrator rules for roadmap maintenance

The roadmap is durable project state, but it is not immutable.

The orchestrator may:

- mark milestones complete when their merged implementation satisfies exit criteria
- split a milestone into smaller releasable increments
- add discovered prerequisite increments
- clarify acceptance criteria based on implementation evidence
- record deferred follow-ups

The orchestrator must not autonomously:

- redefine SignalHub's core product purpose
- replace the backend technology
- choose the cross-platform client technology when the decision is still a human gate
- introduce major distributed infrastructure
- declare `v1.0.0`
- weaken trunk/release guarantees
- bypass required CI or repository protection

Material roadmap changes require a normal reviewed PR and must be visible in repository history.

---

## 7. Current next milestone

Determine this from repository state rather than trusting this section blindly.

After the integration examples (R17), the expected next increment is:

**R18 - v1.0 hardening and contract review**, continuing after R18c

Likely split into bounded increments: the reviews and tests R18 lists. Promotion to `v1.0.0` itself is always the
maintainer's decision. Confirming delivery to a real device (R8 to R10)
still needs the maintainer's Firebase project.

The orchestrator must first inspect `main`, releases and open pull requests to confirm this remains true.
