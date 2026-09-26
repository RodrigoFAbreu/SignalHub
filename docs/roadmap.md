# SignalHub Roadmap

Status: Active  
Development model: lightweight trunk-based development  
Release model: every merge to `main` is releasable and produces a release  
Backend: Java 21 + Quarkus + PostgreSQL  
Client: Flutter, one codebase for Android and iOS (decided in R9)  
Version: one SignalHub version for the whole repository, the `vX.Y.Z` git tag (see [One version, many artifacts](#one-version-many-artifacts))

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

### R18d - End-to-end test from producer to push and client inbox

- a new CI job, `End-to-end (producer to push and client inbox)`, runs the
  packaged backend in Compose with FCM push enabled, pointed at
  `scripts/e2e/fake_fcm.py` (a standard-library stand-in for Google's token
  endpoint and the FCM HTTP v1 API) with a throwaway service account key, so
  no Firebase project or credential is needed
- a producer publishes with the `signalhub` command; the event is persisted,
  dispatched through the outbox and pushed as FCM expects it (the event's ID,
  category and severity as data) only to the client whose preferences allow
  it; FCM's `UNREGISTERED` answer removes another client's push target; the
  delivery metrics count both; the client opens the pushed event by its ID,
  finds both events in its inbox and marks the pushed one read
- no backend, schema or client changes; the app's side of the contract stays
  covered by its tests against its fake server, and receiving a push on a
  real device still needs the maintainer's Firebase project

### R18e - Fresh-install deployment test

- a new CI job, `Deployment (fresh install from docs/deployment.md)`,
  follows the setup of `docs/deployment.md` on a clean runner: `.env` from
  the example with mode 600 and generated secrets, the proxy with Caddy's
  own CA for a name that resolves to the host, a throwaway FCM key mounted
  with the documented permissions, and the documented resource limits
- checks that no secret is logged, that only the documented ports are
  published (the backend on `127.0.0.1`, PostgreSQL not at all), `401` over
  TLS from "another machine", publishing with the `signalhub` command and
  reading the inbox with a client key through the proxy, the management API
  off once the admin token is emptied (clients keep reading), and every
  service back by itself after Docker restarts, as after a reboot
- fixes the documented FCM key permissions: `chmod 400` before
  `sudo chown 10001`, since only the owner may change the mode
- no backend, schema or client changes

### R18f - Compatibility policy and enum evolution

- `docs/architecture.md` gains a *Compatibility* section: what the public
  contract is (product and management API, event schema and enum values,
  push data, operator configuration, health and `signalhub_*` meters,
  forward migrations, the `signalhub` command and SDK), what is not (the
  database schema itself, Java code, built-in metrics, log text), which
  changes are compatible and which need `!`
- enum evolution: adding a category or severity value is a compatible
  `feat`, since clients must accept unknown values (the app shows them as
  "Other"/"Unknown" and keeps them in push preferences; the SDK passes them
  through); the server keeps rejecting unknown request fields and values,
  so producers upgrade after the server
- `/api/v1/` changes only for a redesign that cannot be made compatible
- no code changes: the rules describe what the app, SDK and backend already
  do and test; the maintainer confirms the policy with the v1.0 decision

### R18g - Idempotent publishing

- `POST /api/v1/events` takes an optional `Idempotency-Key` header (1 to 200
  visible ASCII characters), scoped to the producer: the same event with a
  used key stores nothing and answers `200` with the stored event, without a
  second push; a different event with it is `422`; concurrent requests with
  one key store one event (a transaction-scoped advisory lock on the key)
- `V9__add_event_idempotency_key.sql`: nullable `events.idempotency_key` and
  a partial unique index per producer; retention frees a key with its event
- the `signalhub` command's `--idempotency-key` and the SDK's
  `idempotency_key`, so a temporary failure can be retried without a
  duplicate; neither retries by itself
- compatible: without the header nothing changes; tested against real
  PostgreSQL (repeats, every compared field, equivalent JSON and offsets,
  scoping, malformed keys, concurrency, retention, the unique index), in the
  OpenAPI document and in the SDK's tests

### R18h - Upgrade from an older release

- the upgrade job becomes a matrix: besides `Backend container (upgrade from
  the latest release)`, `Backend container (upgrade from v0.13.0)` stores
  the same producer, client, read event and push preferences with v0.13.0,
  upgrades in place to the commit under test, skipping every release and
  migration since (V8 and V9 for now), checks the data, keys, preferences,
  every migration and health, and rolls back to v0.13.0 by restoring the
  backup
- v0.13.0 is the oldest release that stores every kind of data SignalHub
  keeps today; `docs/deployment.md` says upgrades are tested from it on, and
  that older releases apply the same migrations untested
- no backend, schema or client changes

### R18i - Pre-1.0 cleanup: retries in the examples and stale statements

- the GitHub Actions example sends an `Idempotency-Key` naming the failed
  run and its attempt, so `curl --retry` after a timeout no longer stores the
  event twice; a failed re-run is a new attempt and is published again; the
  examples README no longer says publishing is not idempotent
- statements that were true only before later increments are corrected in
  `docs/architecture.md`: the status summary, "no client authentication
  yet", "no list of providers yet; delivery a later release", and the open
  question on which events are pushed (answered by push preferences)
- tests: the step sends the key, and curl's retries repeat the same event
  with the same key; the Compose smoke test runs the step twice for one run
  attempt against the real backend and finds one event
- no backend, schema, client or SDK changes

### R18j - v1.0 readiness review

- every area R18 lists is reviewed against the code, the docs and CI, and
  the outcome is recorded in the v1.0 readiness checklist under R18 in
  section 4: done, reviewed with documented limitations, an open item an
  increment can close, or a decision for the maintainer
- stale or missing statements the review found are corrected: the startup
  summary example in `docs/architecture.md` lacked the event retention
  setting; `docs/development.md` said Compose takes every setting from
  `.env`, while `compose.yaml` passes only some; `docs/architecture.md` now
  says that revoked clients and producer keys are kept and listed, and that
  an event's `createdAt` is taken before it is stored, so an event can
  become visible after a newer one (see open item O1)
- no backend, schema, client or SDK changes

### R18k - Events visible in listing order

- closes open item O1: publishing is serialized with a transaction-scoped
  PostgreSQL advisory lock held until the event commits, and `createdAt` is
  taken under it, one microsecond after the newest stored event's if the
  clock has not moved on or was set back; so events become visible in
  listing order, and a client that stops paging at the newest event it
  already had, or marks read through it, never skips one
- the lock replaces the per-key lock of idempotent publishing (R18g), which
  it covers
- no contract, schema or client changes; tested against real PostgreSQL
  with a publication held uncommitted while another is published

### R18l - Dispatcher tests for revoked clients and repeated dispatches

- closes open item O2: a retry whose client was revoked after the failed
  send is dropped without a send once due; dispatching an event again (a
  second dispatcher took over after the first one's claim expired) sends
  the push again but leaves the pending retry's attempts and due time as
  they were
- no backend, schema, contract or client changes; tested against real
  PostgreSQL with the fake provider

### R18m - Dependabot coverage

- closes open item O3: Dependabot (`pip`) tracks the SDK's build backend in
  `sdk/python/pyproject.toml` and ruff, now pinned in
  `.github/tools/requirements.txt`; Dependabot (`docker`) tracks actionlint,
  now pinned in `.github/tools/actionlint/Dockerfile`, which CI builds
- the tests' PostgreSQL image (Dev Services and Testcontainers) must be the
  Compose image's tag: the `Backend (build + test)` job checks it first, so
  a Dependabot PR that changes only `compose.yaml` fails until they follow
- Flutter has no Dependabot ecosystem: `FLUTTER_VERSION` is raised by hand;
  `docs/development.md#dependency-updates` lists every pin and who updates it
- no backend, schema, contract or client changes

### R18n - Admin listings in an items envelope

- decision D1 (maintainer: wrap them): `GET /api/v1/admin/producers` and
  `GET /api/v1/admin/clients` answer `{"items": [...]}` instead of a bare
  JSON array, like the event listing, so paging or other fields can be added
  later without another breaking change (breaking: releases up to v0.25
  answered arrays; a script reading `.[]` now reads `.items[]`)
- `ProducerList` and `ClientList` in the OpenAPI document; the
  *Compatibility* section says every listing answers an object
- nothing else reads these listings: the app and the SDK use neither, and
  CI's Compose, upgrade, end-to-end and deployment jobs only register
- tested against real PostgreSQL and in the OpenAPI document; no schema or
  client changes

### R18o - Pop-up notifications, app icon and refresh on return

- found while verifying push on the maintainer's Android phone (PR #54,
  `v0.27.0`, superseding PRs #51 to #53): pushes go to an *Events* channel
  of high importance, so they pop up on Android instead of landing silently
  in Firebase's fallback channel; the owner's own settings for the channel
  are kept
- the app has its own launcher and notification icon (`client/icon/`, with
  `render.sh`, which CI lints)
- the inbox and unread count are read again when the app returns to the
  foreground, so pushes that arrived in the background are listed
- a functional review on a real Android device at `v0.27.0` passed its 19
  checks (the "Real-device push" row of the v1.0 readiness checklist); it
  found the read-state defect of R18p
- no backend, schema or contract changes

### R18p - Read-state toggle on the event screen

- the event screen's one read-state action follows the event's state as
  the server last returned it: *Mark as read* (`PUT`) while it is unread,
  for example when marking it read on opening failed, and *Mark as unread*
  (`DELETE`) once it is read, fixing the defect found by the `v0.27.0`
  device review
- the screen shows the event the server returned when marking it read on
  opening and after each change, including when it was read; a failed
  change says why and leaves the state and the action as they were; the
  action is disabled while a change is in flight
- *Mark as unread* returns to the inbox as before; *Mark as read* stays on
  the event; the inbox's bold title, dot and unread count follow both
- widget and controller tests for both directions, a failure in each, and
  an event whose marking on opening failed
- client only: no backend, API or schema changes

### R18q - Device-review tooling in the repository

- the `adb` script of the `v0.27.0` device review is kept in
  `scripts/device-review/` as review tooling, never product runtime code:
  the phone's serial, the server's address, the client ID, the output
  directory and the Compose directory come from the environment or
  arguments, and the producer key, client key and admin token from files;
  there are no defaults naming a device, host, path or key
- a safety guard checks the focused window before every tap and swipe and
  aborts the run unless SignalHub, or the notification shade a check
  opened, is in front
- the checks of the `v0.27.0` review, with R18p's toggle in both
  directions (*Mark as read* on an event whose marking on opening failed
  while the backend was down); the checks that stop the backend or turn
  on airplane mode restore them even when they fail, and push preferences
  are restored
- `scripts/device-review/README.md` covers the prerequisites, usage, the
  guard, and what each check does and changes; `docs/development.md`
  links it
- CI lints it with ruff and runs its unit tests (the focused window, the
  guard's decision, notification channels and records, the screen's
  elements and unread badge, log levels, configuration) on recorded
  samples; the device run itself stays manual
- no backend, API, schema or client changes
- at the start of G1 the guard was found to take a locked phone for the
  shade (both are focused as `NotificationShade`); it now also reads
  whether the lock screen is showing and never touches a locked phone;
  the first G1 runs also found three defects in the script, not in the
  app: `push-preferences` changed the preferences before the paused event
  was dispatched (preferences apply at dispatch); waiting for a restarting
  backend stopped the run on a reset connection; and `popup-over-other-app`
  could take its baseline with an earlier pop-up still on show, looked only
  after the notification was found (Samsung's brief pop-up shows for about
  4 s) and needed more changed pixels than that pop-up changes; all are fixed
- with those fixes (PR #58, `v0.27.4`, which changed only the review
  tooling) the maintainer's automated review of the `v0.27.3` app passed its
  18 checks on their Android phone (foreground, background and killed-app
  push, read state in both directions, push preferences, idempotent
  publishing, backend down and recovering, backend restart, phone offline and
  reconnecting, stale state), finding no app or backend defect; its
  non-blocking observations are queued after 1.0 as R27

### R18r - Stale branch cleanup

- the branches of PRs #51 to #54 (`fix/client-refresh-on-resume`,
  `feat/client-app-icon`, `feat/client-events-notification-channel`,
  `feat/client-device-verification`) were already gone from the remote when
  G1 started; PRs #51 to #53 were closed, superseded by #54, which is
  merged; the only other remote branches are Dependabot's, of open PRs
- nothing to delete, no product change

### R19 - `v1.0.0`

- G1 passed and G2 (decision D4) was given: on 2026-09-26 the maintainer
  signed off their usability review and approved SignalHub for promotion to
  `v1.0.0`, stated in the R19 pull request
- `scripts/release/release.py` no longer turns a major bump into a minor one
  below 1.0: a title with `!` bumps the major version, so R19's own title
  releases `v1.0.0` from `v0.27.5`; its tests cover the promotion, `0.x`
  releases without `!` staying below 1.0, and patch, minor and major
  releases after 1.0
- `docs/development.md#versioning`, `docs/architecture.md#compatibility` and
  `CLAUDE.md` state the SemVer rules from 1.0
- `v1.0.0` is the whole repository's version; the source version fields stay
  development placeholders (see
  [One version, many artifacts](#one-version-many-artifacts))
- no backend, API, schema, client or SDK changes
- the release workflow published `v1.0.0` on 2026-09-26

### R20 - Version identity and the published backend image

- the release workflow builds the backend image from the tagged commit
  natively on an x86-64 and an ARM64 runner
  (`scripts/release/build-image.sh`), pushes both to GHCR by digest and
  tags them as one multi-platform image,
  `ghcr.io/rodrigofabreu/signalhub:X.Y.Z`; only exact versions are tagged
  (no `latest`, no `X.Y`), so a reference always names one release
- the image carries the version, the commit (`SIGNALHUB_VERSION`,
  `SIGNALHUB_REVISION`) and OCI labels for version, revision, source and
  creation time (the commit's time, the same on both platforms); the
  backend reports them at `/q/info` (Quarkus `quarkus-info`, section
  `signalhub`, beside Java and the OS; its `build` and `git` sections are
  off) and at the start of the startup summary; the proxy does not forward
  `/q/`, and the product API has no version endpoint
- any other build reports version `development` and calls itself a
  development build; nothing rewrites the source placeholders
- after pushing, the release pulls the tag on both platforms and checks
  labels, architecture, `/q/info` and the startup summary
  (`scripts/release/check-image.sh`), and only then publishes the GitHub
  release, whose notes name the image and its digest
- provenance (`mode=max`) and SBOM attestations from BuildKit, stored
  beside the image in GHCR (no other service); releases attach no files
  yet, so there are no checksums to publish until R22 and R24 attach some
- pull requests build the image the same way on both platforms with the
  test version `0.0.0-ci` and run the same checks, without pushing; the
  Compose smoke tests check that an image built from source reports
  `development`
- making the GHCR package public is a one-time step for the repository
  owner, documented in `docs/development.md#release-process`; the release
  logs in to pull, so it works while the package is private
- no API, schema or configuration change for operators; `docs/deployment.md`
  mentions the published images, and switching the procedures to them is R21
- the first release run after R20 merged failed before tagging: the ARM64
  image check piped the backend's log into `grep --quiet`, and under
  `pipefail` the SIGPIPE of the log once grep had matched failed the check,
  depending on timing; a `fix(release)` PR reads the log first (in
  `check-image.sh` and one CI step), with a test of `check-image.sh` that
  reproduces the race, and its release is the first to publish the image
  (`v1.1.0`, with R20's own change, on 2026-09-26)

### R21 - Deploying from published images

- each release attaches its deployment files,
  `signalhub-X.Y.Z-deployment.tar.gz` (`compose.yaml`, `.env.example`,
  `proxy/Caddyfile`), and their checksum in `SHA256SUMS`; the release's
  `compose.yaml` runs its published backend image, by version and digest,
  instead of building it (`scripts/release/deployment_files.py`, which
  replaces the repository's build of the backend and refuses a
  `compose.yaml` that builds it differently); the files come with the
  release, not from its tag, because a tag's own `compose.yaml` cannot name
  the version it is about to become, and no version setting is needed
- `docs/deployment.md`: setup downloads and checks the files, then
  `docker compose up --wait` pulls the images; upgrades unpack the new files
  over the old (`.env` and `compose.override.yaml` stay), compare
  `.env.example`, pull and restart; rolling back unpacks the older release's
  files and restores the backup; an install from a clone moves to the files
  with its next upgrade (the Compose project name keeps its volumes), and
  releases up to `v1.1.0`, which have no files, still run from a clone
- the repository's `compose.yaml` still builds from source, for local
  development and for installs that keep upgrading in a clone, so no
  existing install or procedure breaks: `feat`
- the fresh-install job installs from files naming the image CI built for
  the commit (checked against their `SHA256SUMS`) and checks that nothing
  was built; the upgrade jobs start the older release from its files when
  it has them, from its tag with its published image when it has one (`v1.1.0`),
  and built from its tag otherwise (`v0.13.0`), then upgrade to files for
  the commit under test and roll back with the release's files or tag
- tests of the packing (only the backend's build replaced, fixed contents,
  refusals); no backend, API, schema, client or SDK changes

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

Status: complete; R18a (refusing a newer schema), R18b (reading an
event needs the owner's credential), R18c (one error format), R18d (the
end-to-end test), R18e (the fresh-install deployment test), R18f (the
compatibility policy and enum evolution), R18g (idempotent publishing),
R18h (the upgrade from an older release), R18i (pre-1.0 cleanup: retries
in the examples and stale statements), R18j (the v1.0 readiness review) and
R18k (events visible in listing order, closing O1), R18l (dispatcher
tests, closing O2), R18m (Dependabot coverage, closing O3), R18n (admin
listings in an items envelope, decision D1), R18o (pop-up notifications,
app icon and refresh on return), R18p (the read-state toggle on the
event screen), R18q (device-review tooling) and R18r (stale branch cleanup)
are complete (see section 3). The maintainer passed G1 and gave G2, and R19
releases `v1.0.0`. The queue in
[Remaining work to v1.0.0 and after](#remaining-work-to-v100-and-after)
continues after it.

Goal: deliberately declare the first stable SignalHub contract.

Before `v1.0.0`, review:

- public REST API consistency
- authentication/key lifecycle
- event schema (safe retries: idempotent publishing, done in R18g)
- enum evolution strategy (done in R18f)
- pagination
- migrations and upgrade path (refusing to start an older release on a newer schema: done in R18a)
- client/device lifecycle
- push semantics
- error formats (one JSON body for every product API error but `413`: done in R18c)
- configuration compatibility (what operators may rely on: R18f)
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
- full end-to-end test from producer -> API -> persistence -> push -> client inbox (done in R18d)
- fresh-install deployment test (done in R18e)
- upgrade-from-supported-previous-release test (from the latest release and from v0.13.0: done in R18h)

Human gate:

- promotion to `v1.0.0` is always an explicit human decision and must never happen merely because of an automated Conventional Commit version bump.

Exit criteria:

- maintainer explicitly approves the public contract as stable and the repository passes all documented v1.0 readiness checks

### v1.0 readiness checklist

The documented v1.0 readiness checks of the R18 exit criteria. Recorded by
R18j from a review of the code, the docs and CI at `v0.25.2`; an increment
that closes an item updates its row.

| Area | Status | Evidence and notes |
|---|---|---|
| Public REST API consistency | Done | Every endpoint is under `/api/v1`; creating answers `201` with `Location` (a producer key has no resource of its own, so issuing one has no `Location`); every other change answers `200` with the resource; every error but `413` has the JSON error body (R18c); every listing answers `{"items": [...]}` (D1, done in R18n). |
| Authentication and key lifecycle | Reviewed; limitations documented | Producer keys rotate without downtime (issue, switch, revoke). A client key is rotated by registering a new client and revoking the old one; read state is the owner's and stays, push preferences start from the defaults. No key expiry, scopes or rate limiting: `docs/architecture.md#security-limitations`. |
| Event schema | Done | Idempotent publishing (R18g); the contract and how it may change (R18f). |
| Enum evolution | Done | R18f. |
| Pagination | Done | The event listing's keyset cursor matches its documentation, and events become visible in listing order (O1, closed in R18k). The admin listings are unpaginated, in an `items` envelope that leaves room for paging (D1, done in R18n). |
| Migrations and upgrade path | Done | An older release refuses a newer schema (R18a); upgrades tested in CI from the latest release and from v0.13.0 (R18h). |
| Client/device lifecycle | Reviewed; limitations documented | A revoked client loses its push target and gets no pending retries; invalid push targets are dropped. Revoked clients and producer keys are kept and listed. |
| Push semantics | Reviewed; sound | The outbox, leases, retries (up to 5 sends over about 40 minutes), preference filtering and payload match `docs/architecture.md#push-delivery`; at least once, clients deduplicate by event ID. |
| Error formats | Done | R18c. |
| Configuration compatibility | Done | R18f; which settings Compose passes from `.env` is now stated in `docs/development.md#configuration`. |
| Backup/restore | Reviewed; sound | `docs/deployment.md` matches `compose.yaml`; CI backs up, restores, and checks that restoring over data fails. |
| Deployment documentation | Done | Fresh install tested by following the guide (R18e). |
| Security boundaries | Done; limitations documented | Reading an event needs the owner's credential (R18b); the proxy serves only the product API (R16b). |
| Observability | Reviewed; sound | The metrics table matches the code and `MetricsTest`; the startup summary example now matches the code. |
| Test coverage | Done | Unit, PostgreSQL-backed, client, SDK and example tests; Compose smoke tests on x86-64 and ARM64; upgrade, end-to-end and fresh-install jobs. The dispatcher gaps (O2) are closed in R18l. |
| Dependency health | Done; D2 and D3 decided (deferred past 1.0) | Versions and image digests are pinned; Dependabot tracks Actions, Maven, Docker, Compose, pub, the SDK's build backend, ruff and actionlint; CI checks that the tests' PostgreSQL image follows Compose's; Flutter is raised by hand (O3, closed in R18m; `docs/development.md#dependency-updates`). |
| Release automation | Done (R19) | Below 1.0 no PR title could produce `1.0.0`; R19, approved by the maintainer (D4), removed that rule, and its `!` title releases `v1.0.0`. From 1.0 a `!` title bumps the major version. |
| End-to-end, fresh-install and upgrade tests | Done | R18d, R18e, R18h. |
| Real-device push | Done on Android; its defect fixed in R18p | Verified on the maintainer's Android phone with their Firebase project at `v0.27.0` (R18o): a functional review passed its 19 checks (foreground, background, killed app and cold start, pop-up over another app, read state, push preferences, idempotent publishing, backend down and restarted, phone offline). It found that the event screen only offered *Mark as unread*, fixed in R18p (the action now follows the event's read state; verifying it on the device is the maintainer's, with R18q's review). iOS with APNs does not block 1.0 unless another issue requires it. |
| Device-review tooling | Done (R18q) | The review's `adb` script is in `scripts/device-review/`, configured only from the environment, arguments and key files, with a guard that touches the screen only while SignalHub or the shade it opened is in front; CI lints it and unit tests its parsing and guard on recorded samples. The device run stays manual. |
| Real-device review after R18p and R18q | Passed; evidence for G1, not G1 | The maintainer's automated review of `v0.27.3` with R18q's script, as fixed in PR #58 (`v0.27.4`, tooling only): 18 of 18 checks passed, no app or backend defect. Non-blocking observations are queued after 1.0 as R27. |
| Maintainer usability review | Passed (G1) | The maintainer signed off on 2026-09-26, after R18p to R18r. |

Open items, each small enough for one increment and needing no decision:

- **O1 - event creation time and commit order.** Done in R18k: an event
  could commit after a newer one was already listed.
- **O2 - dispatcher tests.** Done in R18l: no test covered a retry whose
  client was revoked meanwhile, or that dispatching an event again leaves a
  pending retry as it is.
- **O3 - Dependabot coverage.** Done in R18m. Not tracked were: the Python SDK's build
  dependency (`sdk/python`), the Dev Services PostgreSQL image in
  `application.properties` (which must stay the Compose version), and the
  ruff, actionlint and Flutter versions pinned in CI.

Decisions for the maintainer (human gates), with the maintainer's answers:

- **D1 - admin listing shape.** `GET /api/v1/admin/producers` and
  `GET /api/v1/admin/clients` answer bare JSON arrays, while the event
  listing answers `{"items", "nextCursor"}`. Keeping arrays is compatible
  but rules out adding paging or fields later without a breaking change;
  wrapping them now (`{"items": [...]}`) is breaking (`!`, a minor bump
  before 1.0) but leaves room. Both are valid for one owner's handful of
  producers and clients. **Decided: wrap them before 1.0; done in R18n.**
- **D2 - Java 25 runtime.** Dependabot proposes the `eclipse-temurin` 25
  JRE (PR #7) and a Maven image on JDK 26 (PR #4), both since closed; their
  successors are PRs #48 and #49. The stack is Java 21 LTS
  and CI tests only on 21; moving to 25 is a stack change, and building on
  a non-LTS JDK 26 would differ from CI. **Decided: keep Java 21 for 1.0;
  Java 25 is a dedicated maintenance milestone after 1.0** (R25).
- **D3 - PostgreSQL 18.** Dependabot proposes `postgres:18-alpine` (PR #5).
  A major version needs a dump and restore of existing data and a changed
  data directory mount in `compose.yaml`, so it is a breaking operator
  change with migration notes, not a routine update. **Decided: keep
  PostgreSQL 17 for 1.0; PostgreSQL 18 is a dedicated maintenance milestone
  after 1.0** (R26).
- **D4 - promotion to `v1.0.0`.** The maintainer approves the public
  contract as stable. The release is then a PR, titled with `!`, that
  removes the pre-1.0 rule from `scripts/release/release.py` and its tests
  and updates `docs/development.md#versioning` and `CLAUDE.md`. **Decided:
  not yet.** The maintainer first verifies push on a real device (Android
  with FCM is enough), and `v1.0.0` needs their explicit approval after that
  test. Push was verified on Android at `v0.27.0` (R18o). **Approved on
  2026-09-26 (G2), after G1; released by R19.**

### Remaining work to v1.0.0 and after

Recorded after the real-device functional review of `v0.27.0`, and extended
with the post-1.0 queue after the review of `v0.27.3` (current release
`v0.27.4`). This table is the queue of the remaining work, in order; each
row is one increment (one PR, one release) or one human gate. Nothing below
may be reordered by an orchestrator, and **nothing after R19 starts before
G1 has passed, G2 is given and R19 has released `v1.0.0`.** The post-1.0
rows are described in section 5, [After v1.0.0](#5-after-v100).

| Order | Item | Kind | Status |
|---|---|---|---|
| 1 | R18p - Read-state toggle on the event screen | Increment (`fix(client)`) | Done (see section 3) |
| 2 | R18q - Device-review tooling in the repository | Increment (`test`) | Done (see section 3) |
| 3 | R18r - Stale branch cleanup | Repository hygiene (no PR, no release) | Done (see section 3) |
| - | Clearing local device-test data | Documentation | Done with this queue ([development.md](development.md#clearing-local-test-data)) |
| 4 | G1 - Maintainer usability review and sign-off | Human gate | Passed (2026-09-26) |
| 5 | G2 - Explicit approval of `v1.0.0` (decision D4) | Human gate | Given (2026-09-26) |
| 6 | R19 - `v1.0.0` | Increment (`!`, the release) | Done (see section 3); released `v1.0.0` on 2026-09-26 |
| 7 | R20 - Version identity and the published backend image | Increment (`feat`) | Done (see section 3) |
| 8 | R21 - Deploying from published images | Increment (`feat`) | Done (see section 3) |
| 9 | R22 - SDK and command version, and SDK files in each release | Increment (`feat`) | Next |
| 10 | G3 - Decisions D5 (push configuration of a distributed app) and D6 (Android release signing key) | Human gate | Not given (may be answered at any time) |
| 11 | R23 - Push configuration served by the backend | Increment (`feat`), only if D5 chooses it | Blocked by G3 |
| 12 | R24 - Installable Android app in each release | Increment (`feat`) | Blocked by G3 (and R23 if D5 chooses it) |
| 13 | R25 - Java 25 (decision D2) | Increment | Blocked until R24 is merged |
| 14 | R26 - PostgreSQL 18 (decision D3) | Increment (`!`) | Blocked until R25 is merged |
| 15 | R27 - Inbox and event-screen polish from the device review | Increment (`fix(client)`) | Blocked until R26 is merged |
| 16 | R28 - Pairing a device: the API | Increment (`feat`) | Blocked until R27 is merged |
| 17 | R29 - Pairing a device: the app | Increment (`feat(client)`) | Blocked until R28 is merged |

How an autonomous run uses it:

1. Confirm from `main`, the releases and the open PRs that the table is
   current (an item's PR may have merged without its row being updated;
   then update the row first, in the next PR).
2. Take the first row whose status is not *Done*. If it is a human gate, or
   *Blocked*, stop and report: nothing after it may start. A gate is passed
   only by the maintainer's answer, stated by the maintainer in a PR or
   issue; a run that finds such an answer records it here and marks the row
   *Done* in its PR. Automation never answers a gate.
3. Implement exactly that one item on a branch from the latest `main`, with
   its tests and docs, and in the same PR mark its row *Done*, mark the
   following row *Next* if it is an increment, and add the item to section
   3 (and, where it applies, the v1.0 readiness checklist).
4. Open the PR, wait for required CI, let GitHub auto-merge it, verify the
   release, and stop. The next run takes the next row.

R18r changes no files; its run records the deleted branches in the PR of
the next item, or, if none is left before a gate, in a `docs` PR that
marks the row *Done*.

#### R18p - Read-state toggle on the event screen

The highest-priority remaining product defect, found by the functional
review. An event's screen (opened from the inbox or by tapping a
notification) has one read-state action, *Mark as unread*
(`client/lib/src/ui/event_screen.dart`, key `markUnread`), whatever the
event's state. Opening an event marks it read in the background, and a
failure leaves it unread, so the screen can show an unread event whose
only action makes it unread.

Implement:

- the action follows the event's current read state: *Mark as read* when
  it is unread, *Mark as unread* when it is read (label, tooltip, icon and
  call: `PUT` or `DELETE /api/v1/events/{id}/read`)
- the state shown is the server's: the event as marking it read on opening
  returned it, and after each change the event the call returned; a failed
  change shows its error and leaves the state and the action as they were
- the event screen stays consistent with the inbox's bold title, dot and
  unread count, which follow the same changes; whether a successful change
  closes the screen (as *Mark as unread* does today) follows the existing
  semantics unless the review of the change finds a reason to change it
- widget and controller tests for both directions, a failure in each, and
  an event whose marking on opening failed; the existing read-state tests
  keep passing
- `client/README.md` and `docs/architecture.md` describe the action if they
  describe the current one

Constraints: client only, no backend, API or schema changes. The Android
notification in the tray has no actions today; adding one is a separate
feature, not this fix. Verifying on a real Android device is the
maintainer's (with R18q's review, if it has landed) and does not block the
merge.

#### R18q - Device-review tooling in the repository

The functional review of `v0.27.0` was driven by a Python script over
`adb` that exists only on the maintainer's machine, outside the
repository. Keep it in `scripts/device-review/` as review tooling, never
product runtime code.

Implement:

- the script, with every value specific to one machine or device taken
  from the environment or arguments: the adb serial (`ANDROID_SERIAL`), the
  server address, the producer and client keys (from files, never on a
  command line), the client ID, the admin token and the output directory;
  no default that names a real device, host, path or key
- the safety guard: before every tap or swipe it checks the focused window
  and refuses to touch the screen (and aborts the run) unless SignalHub is
  in front, or the notification shade where a check opens it
- the checks of the `v0.27.0` review: connected start with a matching
  unread count; the device screen shows push on; the server has an `fcm`
  push target; the *Events* channel at high importance; a foreground push
  goes to the inbox without a system notification; a background push is in
  the *Events* channel and tapping it opens the event and marks it read;
  returning to the app refreshes the inbox; a push to a killed app arrives
  and a cold start opens its event; force-stop and relaunch re-register the
  push target; read state syncs (with R18p's toggle in both directions);
  push preferences filter and pause; idempotent publishing gives one push;
  the backend down, then recovering; a push sent while the phone is offline
  arrives after it reconnects; a pop-up over another app; a backend
  restart; no keyboard focus border; no `WARN`/`ERROR` in the backend log
- checks that change the phone or the stack (airplane mode, stopping the
  backend) restore them even when they fail
- `scripts/device-review/README.md`: prerequisites (a debug build set up
  with a client key, `adb`, `adb reverse`, the local Compose stack with FCM,
  ImageMagick for the screenshot checks), usage, what each check does and
  changes, and that it publishes events (see
  [development.md](development.md#clearing-local-test-data))
- ruff lint and format in CI, and unit tests of the parts that need no
  device (parsing `dumpsys` and `uiautomator` output, the guard's decision)
  with recorded samples; the device run itself stays manual

If the maintainer's copy is not available to the run, write the script from
this description; it is a reference, not a contract.

#### R18r - Stale branch cleanup

Repository hygiene, no product change. The branches of PRs #51 to #54
remain on the remote: `fix/client-refresh-on-resume` (#51, closed),
`feat/client-app-icon` (#52, closed), `feat/client-events-notification-channel`
(#53, closed), superseded by #54, and `feat/client-device-verification`
(#54, merged).

- delete a branch only after confirming that its PR is merged, or closed
  and superseded by a merged one, and that it has no commit whose change is
  missing from `main`
- delete nothing ambiguous: another branch without such confirmation is
  listed in the report and left alone

#### G1 - Maintainer usability review and sign-off

Status: passed; the maintainer signed off on 2026-09-26.

After R18p to R18r, the maintainer uses the app on their device and signs
off, or reports defects; each defect becomes a new row before G1.
Automation never marks G1 done. The automated device review of `v0.27.3`
(18 of 18 checks, see R18q) is evidence for G1, not G1 itself.

#### G2 and R19 - `v1.0.0`

Status: G2 given on 2026-09-26; R19 complete (see section 3).

Decision D4. Only after G1 and the maintainer's explicit approval, stated
in a PR or issue by the maintainer, does the release PR (R19, titled with
`!`) remove the pre-1.0 rule from `scripts/release/release.py` and its
tests and update `docs/development.md#versioning` and `CLAUDE.md`.

#### R20 and later

The post-1.0 rows are described in section 5, [After v1.0.0](#5-after-v100).
Java 25 (decision D2) and PostgreSQL 18 (decision D3), called R20 and R21
before the post-1.0 queue was recorded, are now R25 and R26: the decisions
keep their names, the milestones moved behind release distribution (see
[Order and why](#order-and-why)).

---

## 5. After v1.0.0

Status: planned. **Nothing in this section starts before G1 has passed, the
maintainer has given G2, and R19 has released `v1.0.0`.** The order is the
queue in [Remaining work to v1.0.0 and after](#remaining-work-to-v100-and-after).

Recorded at `v0.27.4` from a review of the repository: every milestone below
closes a gap the code, the docs or the pre-1.0 reviews show, and nothing
below repeats what already exists (see
[Already in place](#already-in-place-not-scheduled-again)).

### One version, many artifacts

SignalHub has **one version**: the repository's `vMAJOR.MINOR.PATCH` git tag
and its GitHub release, computed by `scripts/release/release.py` from the
Conventional Commit titles merged since the previous tag
([development.md](development.md#versioning)). The tag is the version of
record.

```text
SignalHub v1.2.3            (one tag, one GitHub release)
├── backend image           ghcr.io/rodrigofabreu/signalhub:1.2.3   (R20)
├── Android app             SignalHub-1.2.3.apk                     (R24)
├── Python SDK and command  wheel and source archive                (R22)
└── deployment files        compose.yaml, .env.example, proxy/      (R21)
```

- The backend, the app, the SDK and command, and the deployment files are
  parts of one release. Say "SignalHub 1.2.3" (its backend image, its app),
  never "backend 1.2" or "app 1.4". There are no component versions and no
  component release streams: a change to any part is a SignalHub release,
  and every release contains every part.
- The version fields in the sources are **development placeholders**, not
  release versions, and stay so: `backend/pom.xml` (`0.0.0-SNAPSHOT`),
  `client/pubspec.yaml` (`0.1.0+1`) and `sdk/python/pyproject.toml`
  (`0.1.0`). Today the release builds no artifact, and anything built from a
  release's source reports its placeholder: an app built from `v0.27.4` says
  `0.1.0`. R20, R22 and R24 close that gap.
- How artifacts identify their release, the rule for R20 to R24:
  - the release workflow computes the version, then builds each artifact
    from the tagged commit and injects that version (and the commit) at
    build time, for example as a Maven property, Flutter's `--build-name`
    and `--build-number`, or the Python package's build metadata; the
    mechanism is each increment's to choose
  - releasing never rewrites the placeholders and never commits to `main`
  - every artifact of a release reports the same `X.Y.Z` and the commit it
    was built from
  - a build the release did not make (a local build, a CI build of a pull
    request) identifies itself as a development build, never as a release
  - a release whose artifact build fails is not presented as complete; the
    increment that adds the build documents how to finish or repeat it for
    that tag

### Order and why

```text
G1 → G2 → R19 v1.0.0
  → R20 version identity + published backend image
  → R21 deploying from published images
  → R22 SDK and command version + SDK files
  → G3 decisions D5, D6 → R23 push configuration from the backend (if D5 = a)
  → R24 Android app in each release
  → R25 Java 25 → R26 PostgreSQL 18
  → R27 inbox and event-screen polish
  → R28 pairing API → R29 pairing in the app
```

- **Release distribution and version identity come first** (R20 to R24).
  The maintainer asked for it, and the gap was met in practice: testing each
  pre-1.0 release meant checking out its tag and building the backend and
  the app from source. None of it depends on Java 25 or PostgreSQL 18.
- R20 before R21, because deploying from images needs an image; R22 (small
  and independent) before the app, because the app alone needs decisions
  (G3) and possibly an API addition (R23). G3 may be answered at any time,
  including with G2, so that the queue does not stop there.
- **Java 25 (R25) and PostgreSQL 18 (R26) stay two separate increments**,
  in the order decisions D2 and D3 gave them. Java 25 has no dependency on
  distribution either way; with published images it reaches operators as a
  pull instead of a rebuild. PostgreSQL 18 comes after R21 so that its
  migration notes (dump, restore, the changed data directory mount) are
  written once, against the procedure operators use from then on, instead of
  being rewritten one release later.
- Product work follows: R27 is a small client fix with evidence from the
  device review; pairing (R28, R29) is the largest usability gain found, and
  a new API.
- Java 25 and PostgreSQL 18 were numbered R20 and R21 before this queue was
  recorded. Renumbering milestones that never started costs no history and
  keeps the IDs in queue order; decisions D2 and D3 keep their names and
  remain the stable references.

### Release implications

Each row is one PR and one release, versioned by its title under the
post-1.0 rules of [development.md](development.md#versioning): `feat` minor,
every other type patch, `!` major. No version numbers are assigned in
advance; they follow from the queue.

| Item | Expected release | Why |
|---|---|---|
| R20, R22, R24 | minor (`feat`) | new artifacts and a new version surface; nothing existing changes |
| R21 | minor (`feat`) if an install upgrading by the documented procedure keeps working; `!` with migration notes if it needs a new required setting or step | the deployment files and procedure are operator contract (Compatibility section of `docs/architecture.md`) |
| R23 | minor (`feat`) | an addition to the client API; older apps ignore it |
| R25 | patch (`build`) unless it changes something the Compatibility section lists | Java and the JVM are not part of the public contract |
| R26 | major (`!`) with migration notes, unless its implementation finds an upgrade that needs no operator action and the upgrade jobs prove it | a dump and restore and a changed data directory mount are operator-breaking |
| R27 | patch (`fix(client)`) | corrections to existing screens |
| R28, R29 | minor (`feat`) | new, additive capability; manual setup stays |

R26 is expected to be the first major release after 1.0. No other breaking
change is scheduled, and no new API version (`/api/v2`) is planned.

### R20 - Version identity and the published backend image

Status: done (see section 3).

Goal: every release publishes its backend as a multi-platform container
image that identifies itself as that SignalHub release, so a release can be
run without building it.

Motivation: `compose.yaml` builds `signalhub-backend:local` from source;
R16a made the images multi-platform but deliberately published nothing; the
backend cannot say which release it is.

Scope:

- the release workflow builds the backend image from the tagged commit for
  `linux/amd64` and `linux/arm64`, as one multi-platform image from the same
  commit, and pushes it to GHCR as `ghcr.io/rodrigofabreu/signalhub:X.Y.Z`
  (the version without `v`), a tag that is never pushed again; whether
  `latest` (or `X.Y`) is also pushed is decided in the increment and
  documented, and the docs always name an exact version
- the backend knows its version and commit (injected at build): the startup
  configuration summary (R15b) begins with them, and a read-only version
  surface sits under `/q` beside health and metrics (Quarkus's own info
  endpoint or equivalent), so it is not forwarded by the proxy; the product
  API does not gain a version endpoint
- OCI labels on the image: version, revision (commit), source (repository),
  creation time
- the release notes name the image and its digest; SHA-256 checksums for the
  files attached to the release; build provenance attestations where GitHub
  provides them without another service
- a pull request's CI builds the image for both platforms the way the
  release will (without pushing), so a broken release build fails before
  merge; after pushing, the release checks both platforms and the version
  the image reports
- `docs/development.md` (release process) and `docs/deployment.md` (the
  image exists; the switch of the procedure is R21)

Constraints and non-goals:

- GHCR only (no Docker Hub, no other registry); the package is public, so
  pulling needs no login; making it public is a one-time maintainer step in
  the GitHub settings, documented, not a gate
- no secret in the image or its build: the FCM key and every credential stay
  runtime configuration
- no signing service or key management beyond GitHub's attestations
- no change to R16's deployment foundation: TLS, secrets, health, backup and
  resource guidance are unchanged

Validation: `./mvnw verify`, the new image build on both platforms in CI, a
test that a build outside the release reports a development version; after
merge, the release's image pulled on x86-64 and ARM64 reports `X.Y.Z` and the
commit in its labels, its startup summary and its version surface.

Exit criteria: `docker pull ghcr.io/rodrigofabreu/signalhub:<version>` runs
that release's backend on x86-64 and ARM64, and it reports that version.

### R21 - Deploying from published images

Status: done (see section 3).

Goal: operators install, upgrade and roll back a release by pulling its
images instead of building from a checkout.

Scope:

- `compose.yaml` runs the published backend image of a chosen release (for
  example a version setting), keeping a documented way to build from source
  for development and for releases before R20, which have no image
- `docs/deployment.md` setup and upgrades: choose the version, get that
  release's deployment files (from its tag, or attached to the release: the
  increment decides), pull, start and check health; rolling back stays
  restoring the pre-upgrade backup with the older release
- the fresh-install job (R18e) follows the new procedure, with the image CI
  built for the commit under test standing in for the published one (pull
  requests push nothing); the upgrade jobs (R16c, R18h) start an older
  release from its published image when it has one, and build it from its
  tag otherwise
- `docs/development.md`: local development still builds from source

Constraints and non-goals: no new infrastructure; nothing of R16 is redone;
an existing install that follows the documented upgrade keeps its data,
keys and settings; if the change needs a new required setting or step, it is
`!` with migration notes.

Validation: the fresh-install, upgrade and Compose smoke jobs on x86-64 and
ARM64.

Exit criteria: a fresh install and an upgrade that follow
`docs/deployment.md` build nothing, and CI proves both.

### R22 - SDK and command version, and SDK files in each release

Status: next.

Goal: the Python SDK and the `signalhub` command identify the SignalHub
release they belong to, and each release carries them ready to install.

Scope:

- `signalhub --version` prints the SignalHub version (worded as SignalHub's
  version, not a separate SDK version), and the package's metadata
  (`importlib.metadata`) carries it
- the release attaches the SDK's wheel and source archive, built from the
  tag with that version, and their checksums (in the release's
  `SHA256SUMS`, which R21 started); `sdk/python/README.md` shows
  installing the release's wheel
- installing from a tag, as documented today, keeps working; it reports that
  release's version if the build backend can do so without a heavy new
  dependency, otherwise a development version, and the docs recommend the
  release's wheel
- tests of `--version` and of the development identity

Non-goals: publishing on PyPI (deferred); other SDK languages (deferred).

Exit criteria: an SDK installed from a release's files reports that
release's version.

### G3 - Decisions D5 and D6

Human gate. Both need the maintainer; D6 needs a secret only they can
create. They may be answered at any time, before or after `v1.0.0`; R23 and
R24 do not start without the answers.

- **D5 - push configuration of a distributed app.** The app's Firebase
  options (project, app IDs, API keys: `client/firebase-options.json`) are
  the owner's, compiled in with `--dart-define-from-file`; a build without
  them runs without push. An app built by the release therefore needs one
  of:
  - **a. the backend serves them** (R23): the operator gives the backend the
    app's Firebase options next to the service account key, and the app
    reads them after setup. One released app works with any SignalHub server
    and its owner's Firebase project. Costs an API addition and a client
    change. *Recommended.*
  - **b. the release compiles in the maintainer's options** from a GitHub
    Actions secret. Smallest; the app receives push only from a backend
    using the maintainer's Firebase project, so it is the maintainer's
    personal build, and anyone else still builds their own.
  - **c. the released app has no push**; push needs a local build. Useful
    only to try the app.

  In every option the options stay out of git, as `CLAUDE.md` requires.
- **D6 - Android release signing key.** Release builds are signed with the
  local debug key (`client/README.md#signing`), so each machine's builds
  differ and cannot update one another. A released app needs one stable
  key: the maintainer creates it and stores it and its passwords as GitHub
  Actions secrets, never in the repository, and keeps a private backup;
  losing it means every device uninstalls and sets up again. The first
  released app installed over a locally built one also needs an uninstall
  and a new setup (the client key lives in the app's secure storage).

### R23 - Push configuration served by the backend

Status: planned only if D5 chooses **a**; blocked by G3.

Goal: an app that has no compiled-in push options gets them from its
server, so one released app works with any SignalHub server.

Scope:

- an operator setting names the app's push client options (for FCM, the
  Firebase options), validated at startup like the service account key;
  the startup summary says whether it is set
- a client key reads them through the client API (`GET /api/v1/client` or a
  sibling endpoint, the increment decides), in a provider-neutral shape: the
  provider name and an opaque map of options that the backend validates as
  JSON but does not interpret; no Firebase concept enters the domain
- the app initialises push from served options when it has no compiled-in
  ones; compiled-in options keep working and take precedence
- tests against real PostgreSQL, the OpenAPI document, the app against its
  fake server, and the end-to-end job with served options

May be split into the backend and the app (as R11a and R11b were) if one PR
would be too large to review. Compatible (`feat`).

### R24 - Installable Android app in each release

Status: planned; blocked by G3, and by R23 if D5 chooses **a**.

Goal: an operator installs the app of a release from its GitHub release
page, without building it, and the app says which release it is.

Scope:

- the release builds a release APK from the tagged commit, signed with the
  D6 key and set up for push as D5 decided, and attaches it as
  `SignalHub-X.Y.Z.apk` with its SHA-256 checksum (and a provenance
  attestation where GitHub provides it)
- Android `versionName` is `X.Y.Z` and `versionCode` is derived from the
  version so it grows with every release (the rule documented); the
  placeholder in `client/pubspec.yaml` stays for local builds, which
  identify themselves as development builds
- the app shows "SignalHub X.Y.Z" (or its development identity) on the
  *This device* screen
- a pull request's CI builds a release-mode APK (unsigned or with a
  throwaway key) so the release build cannot break unnoticed
- `client/README.md` and `docs/deployment.md`: download, verify the
  checksum, install, update by installing the next release's APK, and the
  one-time uninstall when replacing a locally built app

Constraints and non-goals: no signing or Firebase secret in the repository,
logs or artifacts beyond what D5 allows; no AAB (no store distribution); no
iOS build (it needs the owner's Apple team: unchanged, built in Xcode).

Exit criteria: the APK of a release installs on a phone, sets up with a
client key, receives push as D5 decided, and reports that release.

### R25 - Java 25

Status: planned; decision D2; blocked until R24 is merged.

Goal: move the backend from Java 21 LTS to Java 25 LTS in one step.

Scope: build and runtime images (pinned by digest, multi-platform), the
Maven compiler release, CI's JDK, and every document naming the Java
version (`CLAUDE.md`, `README.md`, `docs/architecture.md`,
`docs/development.md`) together; the tests run on 25 only; the open
Dependabot PRs raising the JDK images (#48 and #49 at the time of writing,
proposing a non-LTS JDK) are closed or superseded; the resource guidance of
R15d is checked again.

Non-goals: adopting new language features in the same PR; a Quarkus upgrade
unless Java 25 requires one; PostgreSQL (R26).

Validation: `./mvnw verify`, the Compose smoke tests on x86-64 and ARM64,
the upgrade, end-to-end and fresh-install jobs; the startup summary reports
Java 25.

### R26 - PostgreSQL 18

Status: planned; decision D3; blocked until R25 is merged.

Goal: move the database to PostgreSQL 18 with a tested, documented path for
existing installs.

Scope: `compose.yaml`'s image (`postgres:18-alpine`, pinned by digest) and
its changed data directory mount; the tests' PostgreSQL image follows
Compose's (checked since R18m); `docs/deployment.md` documents the move as
the backup and restore of R15d into a new volume, and rolling back as
restoring the backup with the previous release; a CI job moves an install
with data from PostgreSQL 17 to 18 by that procedure and checks the data,
keys and preferences; Dependabot PR #5 is closed or superseded.

Non-goals: in-place `pg_upgrade` tooling or automatic upgrade containers,
unless the increment shows one is simpler and CI tests it.

Compatibility: `!` with migration notes in the PR and the release, a major
release (see [Release implications](#release-implications)).

### R27 - Inbox and event-screen polish

Status: planned; blocked until R26 is merged.

Evidence: the non-blocking observations of the device review of `v0.27.3`.

Scope, client only:

- the event screen's read-state action has a visible label, not only an
  icon whose meaning is in a tooltip
- a row's time is readable in full at the default text size for every
  severity (on *High* rows it was cut to `18:…` by the full date)
- when marking an event read on opening fails, the screen says so without
  blocking; the state shown stays the server's, as R18p made it
- while the server is unreachable, one message says so, instead of the
  connection error and the push-registration failure together; a
  push-registration failure is still shown when the server is reachable

Widget tests for each; no API change. Non-goals: the inbox features listed
under [Deferred candidates](#deferred-candidates).

### R28 - Pairing a device: the API

Status: planned; blocked until R27 is merged.

Goal: setting up a device needs neither the admin token on the phone nor
typing a long client key.

Motivation: today the operator registers a client with the admin token
(`curl`), then types the server address and a `shck1_…` key of about 80
characters into the app by hand.

Scope:

- the management API (admin token) creates a pairing for a new client of a
  given name: a one-time code with enough entropy that guessing is
  infeasible, a short expiry (minutes; the increment picks and documents
  it), and a pairing URI holding the server's address and the code, ready to
  show as a QR code with a standard tool (for example `qrencode`,
  documented); where the server's public address comes from is the
  increment's to decide and document
- a product API endpoint, authenticated only by the code, redeems it once
  before expiry: it registers the client exactly as the management API does
  (its own client, its own key, revocable) and returns the key once; an
  expired, used or unknown code gets the usual error body; codes are stored
  hashed and expire unused
- the endpoint is under `/api/` outside `/api/v1/admin/`, so the proxy
  forwards it; the management API still is not forwarded
- registering a client with the management API and manual setup are
  unchanged
- tests against real PostgreSQL (single use, expiry, two concurrent
  redemptions making one client, revoking a paired client), the OpenAPI
  document, and a redemption through the proxy in the Compose smoke test

Constraints: every device keeps its own revocable key, never a shared
permanent one; nothing provider-specific in the pairing; no web UI.
Compatible (`feat`).

### R29 - Pairing a device: the app

Status: planned; blocked until R28 is merged.

Scope:

- setup offers scanning a pairing QR code or pasting the pairing URI; the
  app redeems it, keeps the key in secure storage as today, and continues
  with push registration; the server address and client key stay available
  as manual setup
- scanning uses one well-established Flutter package, justified in the PR;
  the camera permission is asked only when scanning
- clear messages for an expired or used code and an unreachable server
- controller and widget tests against the fake server; `client/README.md`
  and `docs/deployment.md` describe pairing first, manual setup second

Exit criteria: a new phone is set up by scanning a code the operator made,
and becomes its own revocable client.

### Already in place (not scheduled again)

Considered for this queue and already covered: producer keys with rotation
and revocation (R4); per-installation client keys (R6); the inbox, event
details, read state and push preferences in the app (R10 to R12b);
the outbox with bounded retries (R8b, R13); idempotent publishing (R18g);
the Python SDK and command, raw HTTP documentation and five integration
examples (R14, R17); metrics with delivery counters and backlogs, JSON logs,
the startup summary, retention, backup and restore (R15a to R15d); ARM64,
the TLS proxy, secrets, exposure, upgrades, rollback and health monitoring
(R16a to R16c, R18a, R18h); the device-review tooling (R18q). Registering
and revoking producers, keys and clients is already logged at `INFO`, which
is the audit trail a single owner needs; the backend image already runs as
an unprivileged user.

### Deferred candidates

Not scheduled. Each becomes a queue row only when the evidence named here
appears and the maintainer agrees; an orchestrator never schedules one by
itself.

| Candidate | Why not now | What would justify it |
|---|---|---|
| Per-client delivery status (last successful push, last failure and its result, pending retries) in the management API; the app later | Metrics (pushes by result, retries given up, backlogs), the final-failure log line and each client's push target answered every question of the device reviews; R13 found delivery-attempt records unjustified | The owner cannot tell from metrics and logs why a device got no push. Then a last-status per client, not an attempt history, and no dashboard. |
| Inbox filters in the app (producer, category, severity, time: the API has them since R5) and an unread-only view | No usage evidence yet; unread-only needs an API filter | The owner searches a long inbox. The existing API's filters come first. |
| Full-text search | No need shown; R5 ruled it out as premature | Filters prove insufficient. PostgreSQL's own search, no search engine. |
| Unread navigation, grouping in the inbox, further bulk actions, archive or clear | *Mark all as read* and retention cover today's use | Usage evidence from the owner. |
| Quiet hours or schedule-based suppression | Pause and the phone's own do-not-disturb and channel settings cover it (R12a found it unjustified) | A need the phone cannot meet, such as suppression by severity at night. Never a rules engine. |
| Notification grouping on the device | Event volume is low | Bursts of pushes in practice. |
| Rate limiting and brute-force resistance | Keys and pairing codes make guessing infeasible; the management API is not forwarded (`docs/architecture.md#security-limitations`) | Abusive or heavy traffic seen in logs or metrics; the proxy is the first place to limit. |
| Key expiry, key scopes, a separate management port | One owner; rotation and revocation exist; the documented mitigations hold | A producer that must be restricted, or managing from another host. |
| Richer metadata rendering, notification actions and deep links, attachments and images | Metadata is opaque by principle; actions need generic semantics in the event schema | Several unrelated producers needing the same generic capability, with a design that keeps the core producer-agnostic. |
| Web or desktop client | The app covers the owner's phones | The owner needs the inbox away from the phone; the API assumes no platform, so no backend change. |
| Distributed iOS builds, APNs directly | iOS builds need the owner's Apple team; FCM already relays to APNs | An iOS user of released builds. |
| The SDK on PyPI | The release's wheel (R22) and installing from a tag suffice | Producers that cannot install from GitHub. |
| SDKs in more languages | `curl`, the command and Python cover the examples' producers | A producer ecosystem where plain HTTP is a real burden. |

### Rejected

- Component versions or release streams (backend, app or SDK released on
  their own): contradicts [one version](#one-version-many-artifacts).
- Rewriting the source version fields in a release commit: the release
  injects the version at build time instead.
- App store distribution and AABs: SignalHub is self-hosted for one owner.
- Another general deployment-hardening milestone: R16 covers it; R21 only
  moves the procedure to published images.
- A general rules engine, enterprise IAM (OAuth, Keycloak, RBAC) and
  multi-tenancy, as section 6 already says.
- An observability platform (tracing, a log stack, dashboards) beyond the
  metrics and logs of R15.

---

## 6. Explicit non-goals unless added later

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

## 7. Orchestrator rules for roadmap maintenance

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
- answer a human gate (G1, G2, G3) or a decision (D1 to D6) for the maintainer
- start a deferred candidate of section 5 that has not been added to the queue
- give a component (backend, app, SDK) a version or release of its own
- weaken trunk/release guarantees
- bypass required CI or repository protection

Material roadmap changes require a normal reviewed PR and must be visible in repository history.

---

## 8. Current next milestone

Determine this from repository state rather than trusting this section blindly.

The queue in [Remaining work to v1.0.0 and after](#remaining-work-to-v100-and-after)
(section 4) is authoritative. After R21, the expected next item is:

**R22 - SDK and command version, and SDK files in each release**, once the
release workflow has published R21's release: check that the GitHub release
exists and attaches `signalhub-X.Y.Z-deployment.tar.gz` and `SHA256SUMS`
before starting it. If that release failed, correcting it comes first. The
queue then continues with R23 and R24 (with the maintainer's decisions D5 and D6
at G3), then Java 25 (R25) and PostgreSQL 18 (R26), each in its own PR (see
[section 5](#5-after-v100)).

The orchestrator must first inspect `main`, releases and open pull requests to confirm this remains true.
