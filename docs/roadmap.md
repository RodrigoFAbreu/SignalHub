# SignalHub Roadmap

Status: Active  
Development model: lightweight trunk-based development  
Release model: every merge to `main` is releasable and produces a release  
Backend: Java 25 + Quarkus + PostgreSQL  
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
- _Mark all as read_ marks read up to the newest event shown; events that
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

- a _Notifications_ screen (from the inbox menu) sets this client's push
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

- `docs/architecture.md` gains a _Compatibility_ section: what the public
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
  _Compatibility_ section says every listing answers an object
- nothing else reads these listings: the app and the SDK use neither, and
  CI's Compose, upgrade, end-to-end and deployment jobs only register
- tested against real PostgreSQL and in the OpenAPI document; no schema or
  client changes

### R18o - Pop-up notifications, app icon and refresh on return

- found while verifying push on the maintainer's Android phone (PR #54,
  `v0.27.0`, superseding PRs #51 to #53): pushes go to an _Events_ channel
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
  the server last returned it: _Mark as read_ (`PUT`) while it is unread,
  for example when marking it read on opening failed, and _Mark as unread_
  (`DELETE`) once it is read, fixing the defect found by the `v0.27.0`
  device review
- the screen shows the event the server returned when marking it read on
  opening and after each change, including when it was read; a failed
  change says why and leaves the state and the action as they were; the
  action is disabled while a change is in flight
- _Mark as unread_ returns to the inbox as before; _Mark as read_ stays on
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
  directions (_Mark as read_ on an event whose marking on opening failed
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

### R22 - SDK and command version, and SDK files in each release

- each release attaches the Python SDK's wheel and source archive,
  `signalhub-X.Y.Z-py3-none-any.whl` and `signalhub-X.Y.Z.tar.gz`, with
  their checksums in the release's `SHA256SUMS`;
  `scripts/release/sdk_files.py` builds them from a copy of `sdk/python/`
  with the release's version in place of the placeholder (the repository is
  never rewritten), using `build` (pinned in
  `.github/tools/requirements.txt`) and the pinned setuptools, then
  installs the wheel into a new virtual environment and refuses files whose
  `signalhub --version` is not `SignalHub X.Y.Z`
- `signalhub --version` prints `SignalHub X.Y.Z`, SignalHub's version, and
  the package's metadata (`importlib.metadata`) carries `X.Y.Z`; the
  version names one tag and so one commit, and the package carries no other
  build information
- the placeholder in `sdk/python/pyproject.toml` is now `0.0.0.dev0`
  instead of `0.1.0`, which could be mistaken for SignalHub `v0.1.0`; any
  build the release did not make, from a checkout or a tag, reports
  `SignalHub development build`; setuptools cannot take the version from
  the tag without a new build dependency (such as setuptools-scm), so
  installing from a tag keeps working but reports a development build, and
  `sdk/python/README.md` recommends the release's wheel
- the CI Python job builds and checks the files with the test version
  `0.0.0+ci` (Python packaging refuses `0.0.0-ci`); tests of `--version`,
  of the development identity and of the version substitution
- no backend, API, schema or client changes

### R22a - The app's version and commit on the _This device_ screen

- the _This device_ screen has a build entry of two lines: "SignalHub
  X.Y.Z" for an app a release built, "SignalHub development build" for any
  other, and "Commit" with the first 7 characters of the commit it was built
  from, or "Commit unknown" for a build not given it
- both values come in at build time as `--dart-define`s,
  `SIGNALHUB_VERSION` and `SIGNALHUB_REVISION` (the names the backend's
  image build uses), read by `BuildIdentity` in
  `client/lib/src/build_identity.dart`; the placeholder `version:` of
  `client/pubspec.yaml` is never read or shown
- the build commands in `client/README.md` pass the commit
  (`git rev-parse HEAD`) and never the version, so a local build from a
  release's tag says it is a development build; no release builds the app
  until R24, which sets the version through the same define
- widget tests against the fake server: a release build, a build with only
  its commit, a build with neither, and that the placeholder is never shown
- client only: no backend, API or schema changes; the exit criterion's
  check on a real phone is the maintainer's

### R23a - Push client options served by the backend

- `GET /api/v1/client/push-config` (client key): `{"provider", "options"}`,
  the provider name and an opaque map of option names to strings; `404`
  with the usual error body when the operator configured none; OpenAPI
  schema `PushConfig`
- provider-neutral core: a `PushClientOptions` bean at the edge supplies
  them; `PushClientConfig` checks at startup that they are for an enabled
  provider and for one provider only, and logs `Push client options:
served for fcm` or `none`
- FCM edge: `SIGNALHUB_PUSH_FCM_CLIENT_OPTIONS_FILE` names the app's
  `firebase-options.json`; a JSON object of at most 32 names and non-empty
  strings; a file that looks like a service account key is refused, and an
  invalid file stops startup without echoing values; the startup summary
  names the file
- no schema change; unit tests of the file checks and the startup checks,
  API tests against real PostgreSQL (served, not configured, no key,
  revoked key), the OpenAPI document, and the end-to-end job reading the
  served options with a client key
- backend only; the app uses the options in R23b

### R23b - The app sets up push from served options

- a build without compiled-in Firebase options reads
  `GET /api/v1/client/push-config` with its client key after setup, on
  every start and refresh before registering, and starts push with them;
  compiled-in options (`--dart-define-from-file`) keep working and take
  precedence, and then the app never reads the served ones
- the app checks served options before starting Firebase: provider `fcm`,
  every value its platform needs, a numeric sender ID and an app ID of this
  platform and sender; otherwise push stays off and the _This device_
  screen says why: _Push is not configured on this server_ (`404`) or
  _This server's push configuration does not work with this app_ (also
  shown in the inbox); unreadable answers or an unreachable server count as
  a failed registration, retried on the next refresh
- Firebase starts once per process: options that differ from those it
  started with (another server, or replaced by the operator) register
  nothing and ask for a restart, so no token of one Firebase project is
  registered with a server using another; the options are not stored
- setting a push target still needs the client key; the provider-neutral
  `PushService` port is unchanged, `PushConfig` is a provider-neutral model
  and only `FirebasePushService` reads the options
- unit and widget tests against the fake server (served, precedence of
  built-in options, none served, refused and later fixed, malformed,
  unreachable, one start across concurrent refreshes, another server's
  options, a revoked key) and of the option checks; `client/README.md` and
  `docs/architecture.md` document both ways to get the options
- client only: no backend, API or schema changes; receiving a push with
  served options on a real phone is the maintainer's check, with R24's
  released app

### R24 - Installable Android app in each release

- the maintainer created SignalHub's release key (D6) and stored it as the
  repository secrets `ANDROID_RELEASE_KEYSTORE_BASE64`,
  `ANDROID_RELEASE_KEYSTORE_PASSWORD`, `ANDROID_RELEASE_KEY_ALIAS` and
  `ANDROID_RELEASE_KEY_PASSWORD` on 2026-09-27
- the release workflow's `app` job rebuilds the keystore from them in a
  directory it removes at its end and runs `scripts/release/app_files.py`,
  which builds the release-mode APK from the tagged commit with
  `versionName` `X.Y.Z`, `versionCode` `MAJOR × 1000000 + MINOR × 1000 +
PATCH` (refusing a `MINOR` or `PATCH` over 999), `SIGNALHUB_VERSION` and
  `SIGNALHUB_REVISION` for the _This device_ screen (R22a), and no Firebase
  options (the app reads its server's, D5 and R23)
- before the release attaches it, the script checks package, version name
  and code, not debuggable, the commit in the compiled Dart code of every
  ABI, a valid v2 or v3 signature by exactly one signer, and that signer
  being the release key's certificate, never a debug key; a release without
  the secrets fails before tagging
- attached as `SignalHub-X.Y.Z.apk`, in `SHA256SUMS` with the other files,
  with a GitHub build provenance attestation; the release notes name the
  signing certificate's SHA-256 digest
- Gradle signs a release build with the key only when
  `ANDROID_RELEASE_KEYSTORE` is set (and then needs every other variable);
  local builds keep the debug key and call themselves development builds
- the `Client (analyze + test + Android build)` job builds and checks the
  release APK the same way, with the test version `0.0.0-ci` and a
  throwaway key it makes; unit tests of the script on recorded `aapt2`,
  `apksigner` and `keytool` output
- `client/README.md`: download, checksum, attestation and certificate
  check, install, updates, the one-time uninstall when replacing a locally
  built app, and that losing (or leaking) the key means reinstalling on
  every device; `docs/development.md`: the release step, the rule and the
  secrets
- no backend, API or schema changes; the exit criterion's check of the
  released APK on a real phone is the maintainer's

### R25 - Java 25

- the backend builds and runs on Java 25 LTS: `maven.compiler.release` 25,
  the build image `maven:3.9.16-eclipse-temurin-25-noble` and the runtime
  image `eclipse-temurin:25-jre-noble`, both multi-platform and pinned by
  index digest, and JDK 25 in the `Backend (build + test)` job; the tests
  run on 25 only
- the Java 25 JRE image no longer includes `curl`, which the image's health
  check runs, so the runtime stage installs it (`--no-install-recommends`);
  without it, Compose never saw the backend healthy
- the Compose smoke tests (x86-64 and ARM64) check that the startup summary
  reports Java 25
- resource guidance of R15d checked again: with the documented limits the
  backend used about 176 MiB of its 512 MiB after startup (heap limit
  371 MiB with one CPU), PostgreSQL about 48 MiB of 256 MiB; unchanged
- no language features adopted, no Quarkus upgrade (3.39.5 runs on 25); the
  Dependabot PRs raising the images to the non-LTS JDK 24 (#48, #49) are
  superseded
- no API, schema, configuration or client changes: `build`, a patch release

### R26 - PostgreSQL 18

- `compose.yaml` runs `postgres:18-alpine`, pinned by its multi-platform
  index digest; the tests' images (Dev Services, Testcontainers) follow it,
  as CI checks
- PostgreSQL 18 keeps its data in a directory named for its major version,
  so the volume `postgres-data` is mounted at `/var/lib/postgresql`
  instead of `/var/lib/postgresql/data`; the volume keeps its name, so on a
  volume of 17 PostgreSQL 18 exits at once and leaves the data alone, and
  the release it came from still starts on it
- `docs/deployment.md#a-new-postgresql-major-version` moves an install as
  the backup and restore of R15d into a new volume, and rolls back by
  restoring the backup with the previous release; the `Backend container
(upgrade from ...)` jobs, from the latest release and from v0.13.0, do
  this whenever the major version changes: they check the refusal and that
  the volume still holds 17's data, restore into 18 and check the data,
  keys and preferences, then roll back to the release and its backup
- no in-place `pg_upgrade`: dump and restore needs no second image and is
  the procedure operators already use for backups
- Dependabot PR #5 is superseded
- no API, schema or backend code change; an operator change, so `!`: a
  major release with migration notes

### R27 - Inbox and event-screen polish

- the event screen's read-state action is a text button with its icon and
  the label _Mark as read_ or _Mark as unread_, instead of an icon whose
  meaning was only in a tooltip; the keys and wording the device-review
  script uses are unchanged
- an inbox row keeps its time out of the part that is cut: category,
  severity and producer give way to a narrow screen, and the time is shown
  in full for every severity (widget tests at a 360-pixel width)
- when marking an event read on opening fails, a message says _Not marked
  as read_ and why, without blocking the screen; the event stays shown as
  the server's unread state; a later change replaces that message
- a refresh that gets no answer from the server (unreachable or timed out)
  no longer tries push registration, so the inbox shows the one connection
  message instead of that and a failed registration; the push status is
  shown again once the server answers, and a registration failure against
  a reachable server is still shown
- client only: no API, schema or backend change; `fix(client)`, a patch
  release

### R28 - Pairing a device: the API

- `POST /api/v1/admin/pairings` (admin token, `{"name"}`) creates a pairing
  for a new client: a one-time code `shpc1_<22 base64url characters>` (128
  random bits), valid for 10 minutes, and a pairing URI
  `signalhub://pair?server=<public URL>&code=<code>` to show as a QR code
  (`qrencode`, documented in `docs/development.md#pairing-a-device`)
- the public URL is a new optional setting, `SIGNALHUB_PUBLIC_URL`: the
  operator creates pairings on the host, so the request cannot tell the
  server's address; Compose defaults it to `https://` and `SIGNALHUB_DOMAIN`,
  a malformed one stops startup, and without it `uri` is `null`
- `POST /api/v1/pairing` with `Authorization: Bearer <code>` redeems the code
  once before it expires: it registers the client as the management API
  does (its own key, listed and revocable) and returns it with its key
  (`201`); a missing, malformed, unknown, used or expired code gets the
  usual `401`; it is outside `/api/v1/admin/`, so the proxy forwards it
- `V10__create_pairings.sql`: only the SHA-256 of the code is stored;
  redeeming deletes the pairing under its row lock, in the transaction that
  registers the client, so concurrent redemptions make one client; expired
  pairings are deleted when the next one is created
- tests against real PostgreSQL (single use, expiry, eight concurrent
  redemptions making one client, revoking a paired client, the stored hash),
  the OpenAPI document, the configuration, and a pairing redeemed through
  the proxy in the Compose smoke test; registering a client with the
  management API and manual setup are unchanged; compatible (`feat`)

### R29 - Pairing a device: the app

- the setup screen offers pairing first: **Scan pairing code** opens the
  camera (the permission is asked for then, and only then) and reads the
  pairing URI's QR code; **Pairing link** takes a pasted URI; the server
  address and client key stay below, under **Or set up by hand**
- the app redeems the code at the URI's server (`POST /api/v1/pairing`),
  keeps the returned key in secure storage as before and continues with push
  registration and the inbox; the redemption answers the registration, so
  the key is not checked again
- its own messages for a QR code or text that is not a pairing URI, an
  expired or used code, and an unreachable server (named, since the address
  is the operator's `SIGNALHUB_PUBLIC_URL`)
- scanning uses `mobile_scanner` (the most used, maintained Flutter barcode
  scanner, on-device ML Kit and Vision, no network service), behind an
  injected scanner so tests need no camera; `CAMERA` (not required as a
  hardware feature) on Android, `NSCameraUsageDescription` on iOS
- tests of the URI parser, the redemption against the fake backend, the
  controller (pairing, used code, unreachable server, a paired device
  revoked) and the setup screen (scanned, pasted, cancelled, rejected,
  another QR code); `client/README.md` and `docs/deployment.md` describe
  pairing first and manual setup second; no API change; compatible
  (`feat(client)`)

### R30 - An event's link: the API and the SDK

- a new optional event field `link`: one absolute `http` or `https` URL
  with a host, at most 2000 characters (`ValidLink`, over `java.net.URI`),
  stored and returned exactly as sent, `null` when absent; never fetched,
  followed or checked by the backend; relative URLs, other schemes
  (`javascript:`, `file:`, `intent:`, `mailto:`, `ftp:`) and unescaped
  spaces are `400` with a violation for `link`
- `V11__add_event_link.sql`: a nullable `events.link`, checked to be 1 to
  2000 characters; existing events have none
- idempotent publishing compares `link` like the other fields
- the SDK's `link=` and the command's `--link`, passed through unchecked so
  the server decides; the GitHub Actions example sends the run's URL as its
  link; the other examples have no natural URL and are unchanged
- the push payload is unchanged; `docs/architecture.md` (Events, Link,
  Compatibility), the SDK's README, `docs/development.md` and the examples'
  README; an older server rejects an event with a link, so producers are
  upgraded after the server
- tests against real PostgreSQL (valid, absent, exact round trip, too long,
  other schemes, relative, not a string, the column and its check,
  idempotent replays), the OpenAPI document, the SDK and command tests, the
  examples' tests; the Compose smoke test publishes a link with the command
  and reads the GitHub Actions example's link from the real backend
- compatible (`feat`); no client change (the app ignores the new field
  until R31)

### R31 - Opening an event's link in the app

- the event screen shows an event's link among its fields and offers
  **Open link** (labelled, with its icon), which hands it to the platform
  to open outside the app: the system browser, or the app the platform
  assigns to the URL; there is no browser inside the app
- opening uses `url_launcher` (the Flutter team's own plugin for handing a
  URL to the platform, no network service), behind an injected opener so
  tests need no platform channel; Android lists `http` and `https` `VIEW`
  intents under `<queries>` for package visibility; iOS needs nothing, as
  the app never asks whether a URL can be opened
- a tapped notification still opens the event's screen, never the link;
  an inbox row shows a small link icon, and tapping it opens the event
- a link no app opens leaves the owner on the event with a message
- the app accepts only what the server accepts (an absolute `http` or
  `https` URL with a host) and shows any other value, and an older server's
  event without the field, as an event without a link
- tests of the parser (accepted links, other schemes, relative, no host,
  not a string), the controller (the link through the inbox, a read by ID
  and marking read) and the screens (opened with one tap, not opened, the
  inbox icon, a tapped notification, an unusable link, an older server);
  `client/README.md` and `docs/architecture.md` (Client application); no
  API change; compatible (`feat(client)`)

### R32 - Inbox filters and an unread-only view

- a new optional listing parameter `read`: `false` lists only unread
  events, `true` only read ones, anything else is `400` with a violation
  for `read`; combined with the other filters by AND, and served for
  `read=false` by the partial unread index of V6 (no migration)
- a cursor stays a position: paging with `read=false` while events are
  marked read or unread never repeats an event, and a later page lists the
  events after the cursor that are unread by then
- the app's filter button opens a sheet with *Unread only* and chips for
  producers, categories and severities, applied on the server with `read`,
  `producerId`, `category` and `severity` on every page and refresh
  (including after a push or a return to the foreground); a changed filter
  reads the inbox again from the newest page and drops a page in flight
- a bar above the inbox names the active filters, and *Clear* removes
  them all with one tap; an empty result says no event matches
- decided: the filters are not remembered on the device (they last while
  the app runs, so the inbox always starts with every event); the producers
  offered are those of the events read since connecting, kept when a filter
  hides them (client keys cannot list producers; no API was needed); the
  app also drops read events a page brings to the unread-only view, so a
  server older than v2.5.0, which ignores `read`, still shows only unread
  events; *Mark all as read* is offered with *Unread only* but not with a
  producer, category or severity filter, which would mark hidden events
- tests against real PostgreSQL (the filter alone and with others, paging
  while events are marked read and unread, invalid values, the index
  serving both the first and later pages), the OpenAPI document, and the
  app's API client, controller and screens against the fake server
  (including an older server); `docs/architecture.md` (Listing events,
  Client application), `client/README.md`; compatible (`feat`)

### R33 - Each client's last push result in the management API

- `GET /api/v1/admin/clients` and `GET /api/v1/admin/clients/{id}` return
  each client with a new `pushStatus` (schema `ManagedClient`, the fields
  of `Client` and `pushStatus`): `lastSuccess` (`at`, `eventId`) and
  `lastFailure` (`at`, `eventId`, `result`: `UNSUPPORTED_PROVIDER`,
  `INVALID_TARGET`, `TRANSIENT_FAILURE` or `PERMANENT_FAILURE`), each `null`
  until there is one, never the token, and `pendingRetries`; the client
  API, the registration and revocation responses and the app are unchanged
- only the latest results, each overwritten by the next send of its kind;
  no attempt history (R13), no dashboard, no new metrics
- recorded by the dispatch and the retries after each send, in a
  transaction of its own; a send that found no push target is not
  recorded; a failure to record is logged and ignored, so the push is
  neither failed nor sent again and retries are scheduled as before
- `pendingRetries` is counted from `push_retries` when the management API
  is read, not stored, so it cannot drift from the retries
- `V12__add_client_push_results.sql`: nullable `last_push_*` columns on
  `clients`, set together by check constraints, `null` for existing
  clients, so no operator action; not mapped for Hibernate's own updates of
  a client, so a new push target or a revocation never overwrites them;
  the event IDs are not foreign keys, as retention may delete the event;
  revoking a client keeps its results
- tests against real PostgreSQL with the fake provider (no results yet,
  success, overwritten success, permanent failure without the token,
  invalid target, temporary failure then success, retries pending,
  revoked client, nothing on the client API, a failure to record that
  neither fails nor repeats a push), the columns and their checks, the
  OpenAPI document; `docs/architecture.md` (Push dispatch, Client API),
  `docs/development.md`; compatible (`feat`)

### R34 - The Connect page and the pairing notice

- `/connect/`: a static page on the backend's own port (never forwarded by
  the proxy) that creates a pairing with the admin token typed into it,
  kept only in the page's memory, and shows the URI as a QR code with a
  countdown, blurred once expired; it copies the QR code as a PNG image or
  the URI as text (with a selection fallback outside a secure context) and
  downloads the image, so the operator can send a code to someone else;
  without `SIGNALHUB_PUBLIC_URL` it says to set it
- locked down by response headers on `/connect/*`: a
  `Content-Security-Policy` allowing only the page's own scripts, styles
  and requests, no framing, `no-store`, no referrer, `nosniff`
- the QR code is drawn by qrcode-generator 1.4.4 (MIT), a WebJar pinned
  in `pom.xml` and served from its jar: no CDN and no vendored copy
- once a code is redeemed, a `ClientPaired` CDI event, fired after the
  transaction commits, has the `push` package send "New device paired"
  (the name, and data `notice: client-paired` and the client ID) to every
  other client with a push target that has not paused pushes; sent once
  on a thread of its own, without an outbox or retries, so pairing never
  waits for it and a failed notice never fails a pairing; registering a
  client with the management API sends none
- tests: the page, its headers, its scripts resolving (a WebJar version
  out of step with the page fails), no inline script; the notice with the
  fake provider (sent with its text and data, not to paused or revoked
  clients, muted categories and severity not applying, a failed send not
  retried and not failing the pairing); the pairing tests wait for their
  notices so other tests' push counts stay exact; the Compose smoke test
  loads the page and its scripts on the host and gets `404` for them
  through the proxy; `docs/architecture.md` (Pairing, The Connect page,
  Pairing notice), `docs/deployment.md`, `docs/development.md`,
  `client/README.md`; compatible (`feat`)

### R35 - The admin page: every device, admin rights, renaming

- `/admin/`: R34's Connect page becomes the admin page, a static page on
  the backend's own port (never forwarded by the proxy, which answers `404`
  for it); after the admin token, typed in and kept only in the page's
  memory, it lists every client, revoked or not (active first, newest
  first), with its name, whether it is an admin, when it was created or
  revoked, its push target and its last push results, and per device that
  is not revoked: rename, make an admin or take admin rights away, and
  revoke after a confirmation; **Connect a device** is R34's pairing code,
  QR code, copy and download, with a choice to pair an admin device; names
  are always set as text; the same locked-down headers, now on `/admin/*`
- `/connect` and `/connect/` answer `301` to `/admin/` (a hidden resource,
  not in the OpenAPI document), so bookmarks and older notes keep working;
  the Connect page's files are gone (the redirect was removed in R39)
- `admin` on every client response (`Client`, `ManagedClient`, so also a
  client's own registration, registering, pairing and revoking) and on the
  `Pairing` response; optional `admin` in `CreateClientRequest`, for
  registering a client and creating a pairing (`false` when omitted or
  `null`; a string is `400`)
- `PATCH /api/v1/admin/clients/{id}` with `UpdateClientRequest`
  (`name`, `admin`, each optional; at least one, else `400`): `200` with the
  `ManagedClient`, `404` for an unknown ID, **`409` for a revoked client**,
  which never changes; setting a value it already has changes nothing; a
  client key can never change either field
- `V13__add_client_admin.sql`: `clients.admin` and `pairings.admin`,
  `boolean NOT NULL DEFAULT false`, so existing clients and unredeemed
  pairings are not admins and no operator action is needed; the admin flag
  grants nothing yet (R36 builds on it)
- logged at `INFO` with client IDs only: renamed, now an admin device, no
  longer an admin, registered as an admin device, a pairing for an admin
  device; the pairing notice says "New admin device paired" and that the
  device is an admin when it is one
- tests against real PostgreSQL: the migration on a database with clients
  and a pairing, the flag on every response, renaming, granting and taking
  admin rights, both at once, a revoked client, an unknown one, invalid
  bodies, the admin token required, pairing as an admin and its notice;
  the OpenAPI document; the page, its headers on the page and its files,
  its scripts resolving, no inline script, the redirect; the Compose smoke
  test loads the page and its scripts on the host, checks the redirect,
  renames a client, makes it an admin and gets `409` once it is revoked,
  and gets `404` for the page through the proxy; `docs/architecture.md`
  (Clients, Admin devices, Renaming a client, Pairing, The admin page,
  Pairing notice, Client API), `docs/deployment.md`,
  `docs/development.md`, `client/README.md`; compatible (`feat`)

### R36 - Managing devices from an admin device: the API

- `GET /api/v1/client/devices`, `POST /api/v1/client/devices/{id}/admin`
  and `POST /api/v1/client/devices/{id}/revoke`, with a client key, under
  `/api/v1/client` so the proxy forwards them; no request bodies
- only an active admin device's key is accepted; **every other client key
  gets `403 Not an admin device`** on every path, checked before the target
  is looked up, so the answer says nothing about it; a missing, unknown or
  revoked key (a revoked admin included) is the usual `401`; the admin token
  is not a client key (`401`)
- the listing is exactly the management API's (`ClientList` of
  `ManagedClient`, with push results, never a key or a push token)
- making an admin: `200` with the `ManagedClient`; already an admin (the
  caller included) is `200` and changes nothing; `409 Client is revoked`
  for a revoked client; `404` for an unknown ID
- revoking: a client that is not an admin, `200` with the `ManagedClient`,
  its key stops working and its push target is removed; already revoked is
  `200` and changes nothing; **`409 Client is an admin device` for an
  admin, the caller included**; `404` for an unknown ID; taking admin
  rights away and renaming have no device endpoint
- the caller's and the target's rows are locked, in a fixed order, in the
  transaction that makes the change, so an operator revoking the caller or
  taking its rights away is applied before or after, never beside, and two
  admin devices acting on each other cannot deadlock
- logged at `INFO` with client IDs only (`Client <caller> made client <id>
  an admin device`, `Client <caller> revoked client <id>`); a change pushes
  "Device made an admin" or "Device revoked", naming the device that did
  it and pointing to the admin page, with data `notice`
  (`client-made-admin`, `client-revoked`), `clientId` and `byClientId`, to
  every client with a push target and pushes not paused, the calling device
  included (its key may be the stolen one); sent as R34's pairing notice
  (after the commit, once, never failing the request); a request that
  changes nothing or is refused sends nothing; `PairingNotifier` became
  `DeviceNotifier`, sending both kinds
- tests against real PostgreSQL for every caller (an ordinary client, an
  admin, a revoked admin, an admin whose rights were taken away) and every
  target (an ordinary client, an admin, itself, revoked, unknown), the
  listing, the notices with the fake provider (the acting device told, no
  notice for no change or a refusal, a failed notice not failing the
  change), the OpenAPI document; the Compose smoke test lists devices and
  revokes a device from an admin device through the proxy and gets `403`
  for an ordinary one; `docs/architecture.md` (Clients, Admin devices,
  Device management from an admin device, Pairing notice, Client API,
  Logging, Security limitations: what a stolen admin key can do and how the
  operator recovers), `docs/deployment.md`, `docs/development.md`;
  compatible (`feat`)

### R37 - Managing devices in the app

- the app reads `admin` from its registration (`false` when a server older
  than admin devices leaves it out); an admin device's _This device_ screen
  gains a **Devices** section below the build, read with
  `GET /api/v1/client/devices` each time the screen opens or is pulled
  down; other devices, and servers that answer `404` for the listing (older
  than R36), show nothing new and are never asked for it
- on _This device_ rather than a tab of its own: the app has no tabs (the
  inbox is its one home, with the rest in its menu), managing devices is
  occasional, and the screen is already about the device's registration,
  so a tab bar for every device would be new navigation that ordinary
  devices never use
- every device, active ones first in the server's order, then revoked
  ones: its name, _This device_, _Admin device_, _Revoked_; on devices that
  are neither admins nor revoked, a menu with **Make an admin** and
  **Revoke**, each after a confirmation that says what it does and that it
  cannot be undone from a device; nothing on admins (this device included)
  or revoked devices
- a change shows the device as the server returned it; a refused change
  (`409`, the device changed meanwhile) says why and re-reads the list; a
  `403` from any device endpoint, or a registration re-read without
  `admin`, replaces the list with "This device is no longer an admin
  device", re-reads the registration and stops offering management; a
  revoked key returns to setup as everywhere else
- controller tests against the fake backend (listing, both changes, a
  refusal, an unreachable server, rights lost on reading, on a change and
  in a refresh, older servers without `admin` or the endpoints, a revoked
  key), widget tests (an ordinary device, an older server, the list and
  its actions, confirmations and cancelling, a refusal, lost rights), API
  and model tests; `client/README.md`, `docs/architecture.md` (Client
  application); no API change; compatible (`feat(client)`)

### R38 - Pairing codes from an admin device

- `POST /api/v1/client/pairings` (`{"name": ...}`), with a client key,
  under `/api/v1/client` so the proxy forwards it; `201` with the same
  `Pairing` as `POST /api/v1/admin/pairings`, redeemed at the unchanged
  `POST /api/v1/pairing`
- admin-only exactly as R36: every other client key gets `403 Not an admin
  device`, a missing, unknown or revoked key (a revoked admin included) and
  the admin token `401`; the caller's row is locked while the pairing is
  created
- **decided: an admin device never pairs an admin device.** The body has
  only `name` (`admin`, either value, is `400`). A pairing code is the
  bearer secret most likely to leak (it is sent by link or shown as a QR
  code), so a code from a device only ever gives a device that reads
  events; making it an admin is R36's separate, notified step. It also
  keeps a stolen admin device from quietly minting admin devices, in line
  with R36's rule that a stolen admin device must not be able to take over
- the pairing records the device that created it (`pairings.created_by`,
  `V14__add_pairing_created_by.sql`, nullable, so existing pairings and the
  operator's need no action); a code whose device was revoked or lost its
  admin rights before redemption gets `401` and is deleted, so revoking a
  stolen admin device also stops its codes
- logged at `INFO` with IDs only (`Client <caller> created pairing <id>,
  expires at <time>`); the pairing notice names the creating device ("…
  "Anna's phone" created its pairing code. If this was not you, revoke both
  on the admin page.", data `byClientId`) and goes to it too; unchanged
  wording for the operator's codes
- in the app, _Connect a device_ above the device list of an admin device:
  a name, then the pairing URI as a QR code (drawn by the app with the
  pure-Dart `qr` package), a countdown that hides the code once expired,
  and the link with **Copy link** (copying lets the owner paste it into any
  messenger without a share plugin); without a public address the app
  builds the URI from the address it reaches the server at; `403` says the
  device is no longer an admin, `404` (a server older than this) says
  pairing from a device is not supported there and stops offering it
- tests against real PostgreSQL (an ordinary client, an admin, a revoked
  admin, lost rights, validation, the code stopping after revocation or
  lost rights, the creator recorded), the notice with the fake provider,
  the schema, the OpenAPI document; the Compose smoke test creates and
  redeems a code from an admin device through the proxy and gets `403` for
  an ordinary one; controller, widget, API and model tests against the fake
  backend (an older server, lost rights, the countdown, copying);
  `docs/architecture.md` (Pairing, Pairing notice, Client API, Security
  limitations, Client application), `client/README.md`; compatible (`feat`)

### R39 - Remove the /connect redirect

- `ConnectPageRedirect` is gone: `/connect` and `/connect/` answer `404`
  on the backend's own port, as they already did through the proxy; the
  admin page at `/admin/` is unchanged
- tests: `/connect`, `/connect/` and `/connect/connect.js` answer `404`,
  and the OpenAPI document still has no `/connect` path; the Compose smoke
  test expects `404` for `/connect/` and `/connect` on the host and
  through the proxy
- `docs/architecture.md` (The admin page), `docs/deployment.md` (Network
  exposure, and an upgrade note to change bookmarks to `/admin/`),
  `docs/development.md`; not a public contract (hidden from OpenAPI, not
  under `/api`, never forwarded by the proxy), so compatible (`chore`)

### R40 - The device list scrolls to its last device

- the cause: the device list, the event screen and _Connect a device_ gave
  their lists an explicit padding, which replaces the padding a list
  otherwise adds for the system insets; drawn edge to edge, as Android 15
  and later require, their end stayed under the navigation bar. They now
  add the insets to their padding, so the last device, and its actions,
  scroll fully into view clear of the navigation bar
- the inbox and the push preferences keep a list's default padding, which
  already includes the insets: they did not have the fault
- widget tests on a large phone drawn edge to edge (1080 x 2340 pixels at
  2.625x, with a status bar and a navigation bar as insets): more devices
  than fit on the screen, scrolled to the last one, which with its actions
  is fully visible and its actions open; a long event and a pairing code
  in large text scrolled to their end; each fails without the fix;
  compatible (`fix(client)`), no API change

### R41 - Deleting revoked devices: the API and the admin page

- `DELETE /api/v1/admin/clients/{id}` (admin token) and `DELETE
  /api/v1/client/devices/{id}` (an admin device's key, admin only exactly
  as R36: every other client key `403 Not an admin device` before the
  target is looked up, a missing, unknown or revoked key `401`) delete a
  revoked client, an admin or not: `204` with no body; `409 Client is not
  revoked` for an active client, which does not change (the caller
  included); `404` for an unknown ID, so deleting twice is `404`
- the client's push results (columns of its row), its push retries and the
  unused pairing codes it created go with it; events, and their read
  state, stay. `push_retries` and `pairings.created_by` already reference
  `clients` with `ON DELETE CASCADE`, so no migration; a test checks that
  every foreign key to `clients` cascades. A retry is no longer recorded
  for a client deleted while its push was being sent (the insert selects
  the client), so such a dispatch completes instead of failing on the
  foreign key and being sent again
- logged at `INFO` with client IDs only (`Deleted client <id>`, `Client
  <caller> deleted client <id>`); no push notice
- the admin page offers **Delete**, after a confirmation, on revoked
  devices only; active devices keep Rename, admin rights and Revoke
- tests against real PostgreSQL: an active client refused and unchanged,
  a revoked client and a revoked admin deleted by the operator and by an
  admin device with their dependent data while the event stays read, an
  unknown ID, deleting twice, every other client key refused before the
  target is looked up, a revoked admin `401`, the dispatcher with a client
  deleted during its send (fails without the fix); the OpenAPI document,
  the page's script; the Compose smoke test deletes a revoked client with
  the admin token on the host and with an admin device through the proxy
- `docs/architecture.md` (Clients, Deleting a revoked client, Device
  management, the admin page, Client API, Security limitations: revoked
  clients can be deleted and the log is the record, and what deleting adds
  for a stolen admin device), `docs/deployment.md`, `docs/development.md`;
  compatible (`feat`)

### R42 - Deleting revoked devices in the app

- on an admin device's device list (R37), a revoked device, an admin or
  not, offers **Delete** in its menu, after a confirmation that it leaves
  the list for good, that events and their read state stay and that it
  cannot be undone; active devices have none, since they must be revoked
  first. Revoked devices stay greyed out, by hand, since a disabled tile
  would also ignore its menu
- `DELETE /api/v1/client/devices/{id}` (R41): `204` removes the device
  from the list; `409` says why and re-reads the list; `403` says "This
  device is no longer an admin device" in place of the list, as R37's
  changes do; a revoked key returns to setup
- **decided: a server older than R41 is found by the first delete.** The
  server does not say which endpoints it has, and on R41 an unknown ID
  also answers `404`. So a `404` re-reads the list: a device no longer
  listed was deleted meanwhile (by the operator or another admin device)
  and is gone; one still listed means the server has no delete route, as
  does a `405`. The app then says "This server cannot delete devices.
  Update SignalHub, or delete it on the admin page." and stops offering
  *Delete*; that try changed nothing. Probing ahead with a request of its
  own was left out: none tells the two servers apart without the same
  ambiguity
- controller tests against the fake backend (deleting, a device deleted
  meanwhile, an active device refused, an older server answering `404` and
  `405`, lost rights, an unreachable server, a revoked key), widget tests
  (only revoked devices offer it, confirming and cancelling, an older
  server, lost rights), an API test (`204`, `409`, `404`);
  `client/README.md`, `docs/architecture.md` (Client application,
  Deleting a revoked client); no API change; compatible (`feat(client)`)

### R43 - A used pairing code: the API and the admin page

- **decided: an ID in the `Pairing` response and a status endpoint, polled
  while the code is shown.** `POST /api/v1/admin/pairings` and `POST
  /api/v1/client/pairings` add the pairing's `id` (not a secret: it redeems
  nothing); `GET /api/v1/admin/pairings/{id}` (admin token) and `GET
  /api/v1/client/pairings/{id}` (an admin device's key) answer a
  `PairingStatus`: `state` `PENDING`, `REDEEMED` or `EXPIRED`, `expiresAt`,
  and once redeemed `redeemedAt` and `client` (the new device's ID and its
  current name), never a code or a key. Pushing the news to the page was
  left out, as the roadmap said: polling a primary-key lookup every few
  seconds while a code is shown costs nothing for one owner
- **decided: each asks only about its own pairings.** The admin token
  answers only about pairings made with it, an admin device only about
  those it made; another device's pairing, or the operator's, is `404`
  exactly like an unknown ID. The client API part is admin only as R38:
  every other client key `403 Not an admin device` before the pairing is
  looked up, a missing, unknown or revoked key and the admin token `401`
- redeeming no longer deletes the pairing: it marks it with `redeemed_at`
  and `redeemed_by` (`V15__add_pairing_redemption.sql`, nullable, set
  together, `redeemed_by` referencing `clients` with `ON DELETE CASCADE` as
  R41 requires; existing pairings are unredeemed, so no operator action),
  and a redeemed pairing never redeems again, still under the row lock that
  makes one code one client. Pairings, used or not, are deleted when a
  pairing is created more than 10 minutes after they expired
  (`KEPT_AFTER_EXPIRY`), so a late asker still tells used from expired; a
  code whose admin device lost its rights is still deleted when tried.
  Redeeming is unchanged for clients
- the admin page asks every 2.5 seconds, only while a code is shown, and
  once more when it expires; once the code is used, a toast says the device
  (by name) connected with the pairing code, the QR code and link disappear,
  the form goes back to its first state and the device list is read again;
  an expired code is unchanged
- tests against real PostgreSQL (pending, used with the new device named as
  it is now, expired, unknown, an admin device's code asked with the admin
  token, another device's code and the operator's code asked from a device,
  an ordinary client refused before the lookup, lost rights, a revoked
  admin, a used code not redeeming again, recently expired pairings kept and
  older ones deleted with the client kept, a deleted client's pairing gone,
  the new columns and their check), the OpenAPI document, the page's script
  and markup; the Compose smoke test reads the operator's pairing as
  `PENDING` then `REDEEMED` on the host (without the client key in it), and
  an admin device's own code as `REDEEMED` through the proxy, with `403` for
  an ordinary device and `404` for the operator's code;
  `docs/architecture.md` (Pairing, Whether a code was used, Pairing from an
  admin device, the admin page, Client API, Schema), `docs/development.md`,
  `docs/deployment.md`; compatible (`feat`)

### R44 - A used pairing code in the app

- **decided: the screen asks, the controller answers.** _Connect a device_
  (R38) asks `GET /api/v1/client/pairings/{id}` (R43) every 2.5 seconds, as
  the admin page does, only while an unexpired code is shown, the screen is
  open and the app is in the foreground, and once more as the code expires;
  leaving the screen, the code expiring or being used stops it. The
  controller forgets an answer about a code dismissed or replaced meanwhile
- once the code is used, a SnackBar names the device ("Tablet" connected
  with the pairing code.), the QR code and link disappear and the screen
  goes back to its first state (an empty name and _Create pairing code_);
  the device list, read again when the screen closes (R38), shows the new
  device. An expired code is unchanged
- `403` says "This device is no longer an admin device" in place of the
  code, which no longer works, as R38 and R42 do; a revoked key returns to
  setup; any other failure is left to the next poll without a message
- **decided: an older server is found by the pairing, not probed.** A
  `Pairing` without `id` (a server older than R43) is never asked about; a
  `404` or `405` for the status stops asking about that code, and the
  screen stays exactly as before, without an error
- controller tests against the fake backend (pending, used, an answer about
  a dismissed code ignored, lost rights, a revoked key, an unreachable
  server, no `id`, `404` and `405`), widget tests (the message and the
  first state, polling stopping when the screen is left, in the background,
  at expiry, a code used in its last seconds, lost rights, older servers),
  an app test (the new device listed on return), API and model tests; the
  fake backend gained the status endpoint and a device redeeming a code;
  `client/README.md`, `docs/architecture.md` (Client application); no API
  change; compatible (`feat(client)`)

### R45 - SignalHub's own alert: sounds, volume and vibration set in the app

- **decided: a silent channel, and the app plays the alert itself.**
  Android fixes a channel's sound and vibration at creation and has no
  volume per channel, so the app's new *Events* channel
  (`signalhub_events`, high importance, so pushes still pop up) has no
  sound and no vibration, and a broadcast receiver of the app
  (`PushAlertReceiver`), next to Firebase's own, plays the alert for every
  FCM message Firebase shows as a notification (not while the app is in
  the foreground, as Firebase decides it: the in-app notice is kept). The
  channel is created by the app's `Application`, so a push after an update,
  before the app is opened, never falls into Firebase's fallback channel.
  **No backend change**: pushes stay generic notification messages, so
  older apps and any server version behave as before
- replacing the channel is done once: the old `events` channel is deleted,
  and the owner's own settings for it are not carried over
  (`client/README.md`, "Alert", and the release notes say so)
- four original sounds (*Signal*, the default, *Beacon*, *Pulse*,
  *Glass*), synthesised from sine waves by `client/sounds/generate.py`
  and committed as WAV raw resources, with their source and licence in
  `client/sounds/README.md`; CI checks that the committed files are what
  the generator makes. SignalHub's vibration pattern: two short buzzes
  and a long one
- _Notifications → Alert_: **Sound** (the four or none, played when
  chosen and with a play button), **Volume** (10 % to 100 % of the phone's
  notification volume, in steps of 10, played when the slider is let go)
  and **Vibration** (off, light, medium, strong: amplitude 70, 160 or 255,
  or on a phone without amplitude control buzzes of half, full or 1.7
  times the length). Stored in the app's Android preferences, never on
  the server; kept across updates and when the device disconnects
- **decided: the mapping lives in Dart, the Android side only stores and
  plays it.** `AlertSettings.toPlatform` gives the sound's resource, a
  gain and both vibration forms; the defaults the receiver plays before the
  app saved any are bundled as `signalhub_alert_defaults.json`, which a
  test holds equal to the Dart defaults
- the phone is never overridden: nothing during do-not-disturb or on
  silent, only the vibration on vibrate, nothing with SignalHub's
  notifications or the channel turned off or to silent; the sound plays on
  the notification stream and the vibration as a notification's. Previews
  follow the same rules and say when the phone keeps them quiet
- unit tests for the mapping and the stored form, controller tests
  (defaults saved on first start, restored, saved, previewed, a quiet
  phone, failures) and widget tests against the fake server and a fake
  platform; device-review checks `alert-played` (a background push plays
  the chosen sound; a new sound is the next push's) and `alert-quiet` (no
  alert for another app's notification, none during do-not-disturb), the
  channel check now also requiring a silent channel, and the owner's
  by-ear list. The exit criteria need the owner's phone and are left to
  that review. `client/README.md`, `docs/architecture.md` (Client
  application), `docs/development.md`; compatible (`feat(client)`)

### R46 - A separate alert for critical events

- **decided: chosen by the push data's `severity` alone.**
  `PushAlertReceiver` plays the critical alert for `CRITICAL` and the
  general alert for any other severity or one it does not know; the
  producer, category and text are never read. No backend change
- **decided: the silent and do-not-disturb switches apply to every
  critical push**, with or without a different alert, since the
  maintainer's defaults (a critical push sounds on silent, not during
  do-not-disturb) hold with the different alert off, its default. With it
  off, a critical push plays the general sound, volume and vibration
- **decided: the mapping stays in Dart.** Next to the general alert
  (R45's form, unchanged), the app stores `critical` (the settings, read
  back) and `criticalAlert` (what a critical push plays: the general alert
  or its own, and `onSilent` and `duringDoNotDisturb`); the bundled
  defaults gained both, still held equal to the Dart defaults by a test. A
  general alert saved by R45 is kept, and the critical defaults are saved
  next to it when the app is next opened; until then a critical push plays
  the general alert
- **decided: the alarm stream when breaking through.** `AlertPlayer` reads
  the interruption filter and the ringer mode before playing: through
  silent or vibrate only with `onSilent`, through do-not-disturb only with
  `duringDoNotDisturb` and Do Not Disturb access
  (`ACCESS_NOTIFICATION_POLICY`, granted on the system screen the app
  opens; the switch stays off without it, and shows off once it is taken
  away). Breaking through, it plays on the alarm stream and vibrates as an
  alarm, at the alarm volume; total silence keeps it quiet. The app never
  changes the phone's ringer or do-not-disturb
- one more original sound, *Urgent* (two bursts of three harsh notes),
  from `client/sounds/generate.py`, the critical alert's default with 100 %
  and a strong vibration; available to the general alert too
- _Notifications → Alert → Critical events_: **Different alert for
  critical events** (its own sound, volume and vibration, as the general
  alert's, kept while off), **Sound when the phone is on silent**, **Sound
  during Do Not Disturb**
- mapping tests (a critical and every other push with the switch on and
  off, each switch, stored and unknown values, the bundled defaults),
  controller tests (previews on silent and during do-not-disturb with each
  switch on and off, access not given, given later, taken away; R45's
  settings upgraded) and widget tests against the fake server and
  `FakeAlertPlatform`, which now keeps previews quiet as `AlertPlayer`
  does; the choice by severity and the Android playing rules are checked
  by the device review: `alert-critical` (the general alert with the
  switch off, their own with it on, a normal push unchanged) and
  `alert-critical-quiet` (on silent only the critical push plays, as an
  alarm; quiet during do-not-disturb by default), and the owner's by-ear
  list. The exit criteria need the owner's phone and are left to that
  review. `client/README.md`, `docs/architecture.md` (Client application),
  `docs/development.md`; compatible (`feat(client)`)

### R47 - The alert's vibration pattern and length, set in the app

- four patterns, `AlertPattern`: _Short, short, long_ (R45's 90, 90, 90,
  90, 260 ms, the general alert's default), _Steady_ (one buzz), _Heartbeat_
  (80 ms on, 120 off, 200 on) and _Rapid pulse_ (five 60 ms buzzes 60 ms
  apart); three lengths, `AlertLength`: _Short_ (about 0.6 s, the
  default), _Medium_ (about 2 s) and _Long_ (about 5 s)
- **decided: a length repeats the whole pattern** as often as comes
  nearest it, at least once, with the pattern's own pause between repeats
  (400, 600 and 120 ms; _Steady_ has none and runs on as one buzz of the
  length). So the default pattern and length give exactly R45's vibration.
  The intensity steps work on the result as in R45: the same amplitudes,
  or without amplitude control each buzz half, as long or 1.7 times as
  long; the longest (a strong steady long buzz without amplitude control)
  is 8.5 s, and a test holds every combination within 10 s
- the critical alert's own defaults: _Rapid pulse_, _Long_
- **decided: the mapping stays in Dart.** `toPlatform` and the stored
  critical settings gained `pattern` and `length`; the bundled defaults
  too, still held equal to the Dart defaults. Settings saved by R46 are
  read with the pattern and length at their defaults, and **whatever was
  stored is saved again when it differs from what this version stores**,
  so a critical alert of its own takes its new default once the app is
  opened; the general alert's timings are unchanged
- _Notifications → Alert_: **Pattern** (each with a button that vibrates
  it at the chosen length) and **Length** below **Vibration**, for the
  general alert and the critical alert's own; greyed while the vibration
  is off. A change of step, pattern or length previews the vibration alone
- opening the app, or a notification, cancels the app's vibration still
  going (`MainActivity.onResume`); the phone's silent mode,
  do-not-disturb and channel settings apply exactly as in R45 and R46
- mapping tests (each pattern and length, every step with each, the
  10 s bound, stored and unknown values, settings saved before them),
  controller tests (previews, R46's settings upgraded) and widget tests
  against the fake server and `FakeAlertPlatform`; `AlertPlayer` logs the
  pattern and length, and the device review's `alert-critical` also
  requires the critical alert's own to be the long rapid pulse and the
  others the general alert's; the owner's by-hand list gained what only
  they can feel. The exit criteria need the owner's phone and are left to
  that review. `client/README.md`, `docs/architecture.md` (Client
  application), `docs/development.md`; compatible (`feat(client)`)

### R48 - One Settings screen, in folding groups

- one **Settings** screen replaces _Notifications_ and _This device_,
  opened by a **gear icon** in the inbox's top bar, which replaces the
  inbox's menu (left with nothing else once _Disconnect this device_
  moved)
- at the top, always shown, the **Push notifications** switch; below it,
  **folding groups** (`ExpansionTile`) in this order, each header summing
  up its values in one line while folded: **Push filters** (_Normal and
  up · Completed, Info muted · nas muted_), **Alert** (_Signal · 80 % ·
  Medium · Short, short, long · Short_), **Critical alert** (_Same as
  Alert · sounds on silent_) and **This device** (its name and push
  status); every setting inside works, is stored and is previewed as
  before, and nothing moved to or from the API
- **decided: the open groups are kept in the platform's secure storage**
  (`SecureOpenGroupsStore`, the one store the app already had), not in a
  new dependency; nothing in them is secret. They belong to the device,
  like the alert, and stay when it disconnects; a store that fails leaves
  the groups folded and still working
- while push is paused, Push filters, Alert and Critical alert are greyed,
  with _Applies once push notifications are on_ in their headers, and
  still change
- _This device_ holds the name and server, push status, build, and
  **Disconnect this device**, which now asks for a confirmation first and
  returns to setup
- on an admin device, a **Devices** row (_7 devices · 2 admins_) opens
  device management and _Connect a device_ on a screen of their own,
  unchanged (`DevicesScreen`)
- the device review follows the screen: the gear icon's _Settings_, the
  group titles, and a group unfolded only when its first rows are not
  already shown below its header (the app remembers open groups); its
  README, unit tests and sample updated
- widget tests (the gear icon, each group folded and unfolded, summaries
  for the defaults and for changed values, a summary following a change,
  the open groups kept and read at start, a failing store, greyed groups
  while push is off, the Devices row only on an admin device, disconnecting
  after a confirmation), summary unit tests and controller tests; the
  existing tests reach their settings through the new screen. The exit
  criteria need the owner's phone and are left to the next device review.
  `client/README.md` (a new _Settings_ section), `docs/architecture.md`
  (Client application), `docs/development.md`; compatible (`feat(client)`)

### R49 - The pending Dependabot updates

- all three Dependabot updates open on 2026-09-29 applied together, and
  no other Dependabot pull request had opened meanwhile:
  - #6: `maven-compiler-plugin` 3.15.0 to 3.16.0 (`backend/pom.xml`)
  - #8: `maven-surefire-plugin` 3.5.6 to 3.6.0 (`backend/pom.xml`); its
    one red check, _Backend container (upgrade from v0.13.0)_, was Docker
    Hub resetting the connection while authorizing, not the update
  - #9: `actions/setup-java` 5 to 6 in `ci.yml` (the backend and client
    jobs) and `release.yml` (the Android build)
- **none left out, and no adjustment needed**: the release notes break
  nothing SignalHub uses. The compiler plugin changes incremental
  recompilation (it now also recompiles when dependencies change), not
  `-Xlint:all`, `-Werror` or annotation processing; Surefire 3.6.0 adds
  JUnit Platform features and fixes, and reports `@AfterAll` failures as
  errors again, which fails a build only on a real test failure;
  setup-java 6 runs on Node 24 (as `actions/checkout@v7` already does on
  the same hosted runners), drops only the legacy AdoptOpenJDK
  distributions (SignalHub uses Temurin) and caches the Maven wrapper's
  distribution apart from the dependencies; every input SignalHub passes
  (`distribution`, `java-version`, `cache`, `cache-dependency-path`) is
  unchanged
- validated by `./mvnw verify` (Java 25, tests against PostgreSQL through
  Dev Services, Spotless, SpotBugs) and CI on every job, including the
  release-image, upgrade and Android jobs; the Dependabot pull requests
  are closed as superseded after it merges. Dependabot's configuration is
  unchanged; compatible (`build`)

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

| Area                                        | Status                                      | Evidence and notes                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Public REST API consistency                 | Done                                        | Every endpoint is under `/api/v1`; creating answers `201` with `Location` (a producer key has no resource of its own, so issuing one has no `Location`); every other change answers `200` with the resource; every error but `413` has the JSON error body (R18c); every listing answers `{"items": [...]}` (D1, done in R18n).                                                                                                                                                                                                                                                        |
| Authentication and key lifecycle            | Reviewed; limitations documented            | Producer keys rotate without downtime (issue, switch, revoke). A client key is rotated by registering a new client and revoking the old one; read state is the owner's and stays, push preferences start from the defaults. No key expiry, scopes or rate limiting: `docs/architecture.md#security-limitations`.                                                                                                                                                                                                                                                                       |
| Event schema                                | Done                                        | Idempotent publishing (R18g); the contract and how it may change (R18f).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Enum evolution                              | Done                                        | R18f.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Pagination                                  | Done                                        | The event listing's keyset cursor matches its documentation, and events become visible in listing order (O1, closed in R18k). The admin listings are unpaginated, in an `items` envelope that leaves room for paging (D1, done in R18n).                                                                                                                                                                                                                                                                                                                                               |
| Migrations and upgrade path                 | Done                                        | An older release refuses a newer schema (R18a); upgrades tested in CI from the latest release and from v0.13.0 (R18h).                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Client/device lifecycle                     | Reviewed; limitations documented            | A revoked client loses its push target and gets no pending retries; invalid push targets are dropped. Revoked clients and producer keys are kept and listed.                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Push semantics                              | Reviewed; sound                             | The outbox, leases, retries (up to 5 sends over about 40 minutes), preference filtering and payload match `docs/architecture.md#push-delivery`; at least once, clients deduplicate by event ID.                                                                                                                                                                                                                                                                                                                                                                                        |
| Error formats                               | Done                                        | R18c.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Configuration compatibility                 | Done                                        | R18f; which settings Compose passes from `.env` is now stated in `docs/development.md#configuration`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Backup/restore                              | Reviewed; sound                             | `docs/deployment.md` matches `compose.yaml`; CI backs up, restores, and checks that restoring over data fails.                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Deployment documentation                    | Done                                        | Fresh install tested by following the guide (R18e).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Security boundaries                         | Done; limitations documented                | Reading an event needs the owner's credential (R18b); the proxy serves only the product API (R16b).                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Observability                               | Reviewed; sound                             | The metrics table matches the code and `MetricsTest`; the startup summary example now matches the code.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| Test coverage                               | Done                                        | Unit, PostgreSQL-backed, client, SDK and example tests; Compose smoke tests on x86-64 and ARM64; upgrade, end-to-end and fresh-install jobs. The dispatcher gaps (O2) are closed in R18l.                                                                                                                                                                                                                                                                                                                                                                                              |
| Dependency health                           | Done; D2 and D3 decided (deferred past 1.0) | Versions and image digests are pinned; Dependabot tracks Actions, Maven, Docker, Compose, pub, the SDK's build backend, ruff and actionlint; CI checks that the tests' PostgreSQL image follows Compose's; Flutter is raised by hand (O3, closed in R18m; `docs/development.md#dependency-updates`).                                                                                                                                                                                                                                                                                   |
| Release automation                          | Done (R19)                                  | Below 1.0 no PR title could produce `1.0.0`; R19, approved by the maintainer (D4), removed that rule, and its `!` title releases `v1.0.0`. From 1.0 a `!` title bumps the major version.                                                                                                                                                                                                                                                                                                                                                                                               |
| End-to-end, fresh-install and upgrade tests | Done                                        | R18d, R18e, R18h.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Real-device push                            | Done on Android; its defect fixed in R18p   | Verified on the maintainer's Android phone with their Firebase project at `v0.27.0` (R18o): a functional review passed its 19 checks (foreground, background, killed app and cold start, pop-up over another app, read state, push preferences, idempotent publishing, backend down and restarted, phone offline). It found that the event screen only offered _Mark as unread_, fixed in R18p (the action now follows the event's read state; verifying it on the device is the maintainer's, with R18q's review). iOS with APNs does not block 1.0 unless another issue requires it. |
| Device-review tooling                       | Done (R18q)                                 | The review's `adb` script is in `scripts/device-review/`, configured only from the environment, arguments and key files, with a guard that touches the screen only while SignalHub or the shade it opened is in front; CI lints it and unit tests its parsing and guard on recorded samples. The device run stays manual.                                                                                                                                                                                                                                                              |
| Real-device review after R18p and R18q      | Passed; evidence for G1, not G1             | The maintainer's automated review of `v0.27.3` with R18q's script, as fixed in PR #58 (`v0.27.4`, tooling only): 18 of 18 checks passed, no app or backend defect. Non-blocking observations are queued after 1.0 as R27.                                                                                                                                                                                                                                                                                                                                                              |
| Maintainer usability review                 | Passed (G1)                                 | The maintainer signed off on 2026-09-26, after R18p to R18r.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |

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
  after 1.0** (R26). **Done in R26.**
- **D4 - promotion to `v1.0.0`.** The maintainer approves the public
  contract as stable. The release is then a PR, titled with `!`, that
  removes the pre-1.0 rule from `scripts/release/release.py` and its tests
  and updates `docs/development.md#versioning` and `CLAUDE.md`. **Decided:
  not yet.** The maintainer first verifies push on a real device (Android
  with FCM is enough), and `v1.0.0` needs their explicit approval after that
  test. Push was verified on Android at `v0.27.0` (R18o). **Approved on
  2026-09-26 (G2), after G1; released by R19.**
- **D5 - push configuration of a distributed app** (G3; options in
  [G3](#g3---decisions-d5-and-d6)). **Decided on 2026-09-26: option a, the
  backend serves the app's client-safe push configuration** (R23). Never
  the maintainer's Firebase options compiled into the released app.
- **D6 - Android release signing key** (G3). **Decided on 2026-09-26: one
  stable release signing key for every official APK**, created by the
  maintainer, kept only in GitHub Actions secrets and a private offline
  backup (R24).

### Remaining work to v1.0.0 and after

Recorded after the real-device functional review of `v0.27.0`, and extended
with the post-1.0 queue after the review of `v0.27.3` (current release
`v0.27.4`). This table is the queue of the remaining work, in order; each
row is one increment (one PR, one release) or one human gate. Nothing below
may be reordered by an orchestrator, and **nothing after R19 starts before
G1 has passed, G2 is given and R19 has released `v1.0.0`.** The post-1.0
rows are described in section 5, [After v1.0.0](#5-after-v100).

| Order | Item                                                                                             | Kind                                   | Status                                                                           |
| ----- | ------------------------------------------------------------------------------------------------ | -------------------------------------- | -------------------------------------------------------------------------------- |
| 1     | R18p - Read-state toggle on the event screen                                                     | Increment (`fix(client)`)              | Done (see section 3)                                                             |
| 2     | R18q - Device-review tooling in the repository                                                   | Increment (`test`)                     | Done (see section 3)                                                             |
| 3     | R18r - Stale branch cleanup                                                                      | Repository hygiene (no PR, no release) | Done (see section 3)                                                             |
| -     | Clearing local device-test data                                                                  | Documentation                          | Done with this queue ([development.md](development.md#clearing-local-test-data)) |
| 4     | G1 - Maintainer usability review and sign-off                                                    | Human gate                             | Passed (2026-09-26)                                                              |
| 5     | G2 - Explicit approval of `v1.0.0` (decision D4)                                                 | Human gate                             | Given (2026-09-26)                                                               |
| 6     | R19 - `v1.0.0`                                                                                   | Increment (`!`, the release)           | Done (see section 3); released `v1.0.0` on 2026-09-26                            |
| 7     | R20 - Version identity and the published backend image                                           | Increment (`feat`)                     | Done (see section 3)                                                             |
| 8     | R21 - Deploying from published images                                                            | Increment (`feat`)                     | Done (see section 3)                                                             |
| 9     | R22 - SDK and command version, and SDK files in each release                                     | Increment (`feat`)                     | Done (see section 3)                                                             |
| 10    | R22a - The app's version and commit on the _This device_ screen                                  | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 11    | G3 - Decisions D5 (push configuration of a distributed app) and D6 (Android release signing key) | Human gate                             | Given (2026-09-26): D5 = a, D6 = one stable release key                          |
| 12    | R23a - Push client options served by the backend (first half of R23)                             | Increment (`feat`)                     | Done (see section 3)                                                             |
| 12b   | R23b - The app sets up push from served options (second half of R23)                             | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 13    | R24 - Installable Android app in each release                                                    | Increment (`feat`)                     | Done (see section 3)                                                             |
| 14    | R25 - Java 25 (decision D2)                                                                      | Increment (`build`)                    | Done (see section 3)                                                             |
| 15    | R26 - PostgreSQL 18 (decision D3)                                                                | Increment (`!`)                        | Done (see section 3)                                                             |
| 16    | R27 - Inbox and event-screen polish from the device review                                       | Increment (`fix(client)`)              | Done (see section 3)                                                             |
| 17    | R28 - Pairing a device: the API                                                                  | Increment (`feat`)                     | Done (see section 3)                                                             |
| 18    | R29 - Pairing a device: the app                                                                  | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 19    | R30 - An event's link: the API and the SDK                                                       | Increment (`feat`)                     | Done (see section 3)                                                             |
| 20    | R31 - Opening an event's link in the app                                                         | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 21    | R32 - Inbox filters and an unread-only view                                                      | Increment (`feat`)                     | Done (see section 3)                                                             |
| 22    | R33 - Each client's last push result in the management API                                       | Increment (`feat`)                     | Done (see section 3)                                                             |
| 23    | R34 - The Connect page and the pairing notice                                                    | Increment (`feat`)                     | Done (see section 3)                                                             |
| 24    | R35 - The admin page: every device, admin rights, renaming                                       | Increment (`feat`)                     | Done (see section 3)                                                             |
| 25    | R36 - Managing devices from an admin device: the API                                             | Increment (`feat`)                     | Done (see section 3)                                                             |
| 26    | R37 - Managing devices in the app                                                                | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 27    | R38 - Pairing codes from an admin device                                                         | Increment (`feat`)                     | Done (see section 3)                                                             |
| 28    | R39 - Remove the /connect redirect                                                               | Increment (`chore`)                    | Done (see section 3)                                                             |
| 29    | R40 - The device list scrolls to its last device                                                 | Increment (`fix(client)`)              | Done (see section 3)                                                             |
| 30    | R41 - Deleting revoked devices: the API and the admin page                                       | Increment (`feat`)                     | Done (see section 3)                                                             |
| 31    | R42 - Deleting revoked devices in the app                                                        | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 32    | R43 - A used pairing code: the API and the admin page                                            | Increment (`feat`)                     | Done (see section 3)                                                             |
| 33    | R44 - A used pairing code in the app                                                             | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 34    | R45 - SignalHub's own alert: sounds, volume and vibration set in the app                         | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 35    | R46 - A separate alert for critical events                                                       | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 36    | R47 - The alert's vibration pattern and length, set in the app                                   | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 37    | R48 - One Settings screen, in folding groups                                                     | Increment (`feat(client)`)             | Done (see section 3)                                                             |
| 38    | R49 - The pending Dependabot updates                                                             | Increment (`build`)                    | Done (see section 3)                                                             |

How an autonomous run uses it:

1. Confirm from `main`, the releases and the open PRs that the table is
   current (an item's PR may have merged without its row being updated;
   then update the row first, in the next PR).
2. Take the first row whose status is not _Done_. If it is a human gate, or
   _Blocked_, stop and report: nothing after it may start. A gate is passed
   only by the maintainer's answer, stated by the maintainer in a PR or
   issue; a run that finds such an answer records it here and marks the row
   _Done_ in its PR. Automation never answers a gate.
3. Implement exactly that one item on a branch from the latest `main`, with
   its tests and docs, and in the same PR mark its row _Done_, mark the
   following row _Next_ if it is an increment, and add the item to section
   3 (and, where it applies, the v1.0 readiness checklist).
4. Open the PR, wait for required CI, let GitHub auto-merge it, verify the
   release, and stop. The next run takes the next row.

R18r changes no files; its run records the deleted branches in the PR of
the next item, or, if none is left before a gate, in a `docs` PR that
marks the row _Done_.

#### R18p - Read-state toggle on the event screen

The highest-priority remaining product defect, found by the functional
review. An event's screen (opened from the inbox or by tapping a
notification) has one read-state action, _Mark as unread_
(`client/lib/src/ui/event_screen.dart`, key `markUnread`), whatever the
event's state. Opening an event marks it read in the background, and a
failure leaves it unread, so the screen can show an unread event whose
only action makes it unread.

Implement:

- the action follows the event's current read state: _Mark as read_ when
  it is unread, _Mark as unread_ when it is read (label, tooltip, icon and
  call: `PUT` or `DELETE /api/v1/events/{id}/read`)
- the state shown is the server's: the event as marking it read on opening
  returned it, and after each change the event the call returned; a failed
  change shows its error and leaves the state and the action as they were
- the event screen stays consistent with the inbox's bold title, dot and
  unread count, which follow the same changes; whether a successful change
  closes the screen (as _Mark as unread_ does today) follows the existing
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
  push target; the _Events_ channel at high importance; a foreground push
  goes to the inbox without a system notification; a background push is in
  the _Events_ channel and tapping it opens the event and marks it read;
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
  (`0.1.0` until R22 made it `0.0.0.dev0`). At `v0.27.4` the release built no
  artifact, and anything built from a release's source reported its
  placeholder: an app built from `v0.27.4` says `0.1.0`. R20, R22 and R24
  close that gap.
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
  → R22a the app's version and commit on the This device screen
  → G3 decisions D5, D6 → R23 push configuration from the backend (if D5 = a)
  → R24 Android app in each release
  → R25 Java 25 → R26 PostgreSQL 18
  → R27 inbox and event-screen polish
  → R28 pairing API → R29 pairing in the app
  → R30 an event's link (API, SDK) → R31 opening it in the app
  → R32 inbox filters and unread-only
  → R33 each client's last push result
  → R34 the Connect page and the pairing notice
  → R35 the admin page → R36 device management API for admin devices
  → R37 device management in the app → R38 pairing codes from an admin device
  → R39 removing the /connect redirect
  → R40 the device list's last device → R41 deleting revoked devices (API,
    admin page) → R42 deleting them in the app → R43 a used pairing code
    (API, admin page) → R44 a used pairing code in the app
  → R45 SignalHub's own alert, set in the app → R46 a separate alert for
    critical events
```

- **Release distribution and version identity come first** (R20 to R24).
  The maintainer asked for it, and the gap was met in practice: testing each
  pre-1.0 release meant checking out its tag and building the backend and
  the app from source. None of it depends on Java 25 or PostgreSQL 18.
- R20 before R21, because deploying from images needs an image; R22 (small
  and independent) before the app, because the app alone needs decisions
  (G3) and possibly an API addition (R23). G3 may be answered at any time,
  including with G2, so that the queue does not stop there.
- **R22a comes before G3** at the maintainer's request (2026-09-26, after
  installing `v1.3.0` on the phone): which build a phone runs could only be
  found with `adb` or by remembering how it was built. It needs no
  decision, and R24 then only has to feed the release's version into it.
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
- **R30 to R33 were added by the maintainer on 2026-09-27**, from the
  [deferred candidates](#deferred-candidates), in order of daily value to
  one owner whose producers are CI, coding agents, scripts and the homelab:
  - an event's link (R30, R31) first: nearly every such producer has a
    natural URL (the pull request, the failed run, the waiting session),
    and today the owner reads the notification and then finds it by hand.
    The API and SDK come first so producers can send links before the app
    shows them, as R11a and R11b were split.
  - inbox filters (R32) next: the API has had them since R5, so it is
    mostly app work, and the inbox gets noisy once several producers are
    active.
  - each client's last push result (R33) last: "why did my phone not
    buzz?" is answered today by metrics and logs, from a terminal; a last
    result per client answers it from the management API.
- **R34 was added by the maintainer on 2026-09-27**, after pairing a
  phone: making a pairing code took a terminal on the host, and there was
  no way to hand a code to someone else. The Connect
  page does it in a browser, on the host only, like the management API it
  calls; since a shared code gives a device to whoever holds it, the
  owner's devices are told whenever one pairs. A public page with a login,
  and approving new devices from a paired one, were considered and left
  out: the first puts the admin credential on the internet, the second
  still needs a first device paired another way.
- **R35 to R38 were added by the maintainer on 2026-09-27**, after R34
  (the Connect page) was built: the owner wants trusted devices of
  their own to manage the others from the app, and one page on the host to
  manage every device. The maintainer's answers, recorded here so no
  increment has to ask again:
  - the Connect page becomes an **admin page** on the host (R35): every
    device, renaming, making a device an admin and taking admin rights
    away, revoking, and adding devices, an admin or not. It is the only
    place where admin rights are taken away.
  - an **admin device** can see every device, make another device an
    admin, and revoke devices that are not admins (R36, R37). It can do
    nothing to another admin: no demoting and no revoking, so a stolen
    admin phone cannot lock the owner out of their other admin devices.
  - **pairing codes from an admin device** (R38) are wanted, as a later
    improvement in a release of their own, not with R35 to R37.
  - the API (R36) comes before the app (R37), as R28 and R29 were split,
    so each release is complete and the app never calls an API that does
    not exist yet.
- **R40 to R44 were added by the maintainer on 2026-09-27**, from the
  functional review of `v2.11.1`. The maintainer's answers, recorded here
  so no increment has to ask again:
  - the app's device list cuts off its last device when the list is long
    (R40); a fix, so it comes first.
  - **revoked devices can be deleted**, on the admin page and in the app,
    so devices paired again do not pile up as duplicates in the list;
    an active device has no delete: it must be revoked first (R41, R42).
    This replaces the earlier choice to keep revoked clients as a record
    (Security limitations of `docs/architecture.md`); the `INFO` log lines
    of registering, revoking and deleting remain the record.
  - when a pairing code is used, the admin page shows a toast naming the
    device that connected with it and goes back to its first state (the
    device name and _Create pairing code_), the QR code gone (R43); the
    app's _Connect a device_ does the same (R44).
  - the API comes before the app in both pairs, as R36 and R37 were split,
    so the app never calls an API that does not exist yet.
- **R45 and R46 were added by the maintainer on 2026-09-29**, once
  producers of their own (the workflow lanes) started pushing to the
  owner's phone. The maintainer's answers, recorded here so no increment
  has to ask again:
  - a SignalHub push must be recognisable without looking at the phone,
    by a sound and a vibration of its own, told apart from every other
    app's notifications (R45).
  - the owner sets the alert in the app: one of three or four bundled
    sounds, the alert's volume and the vibration's intensity (R45).
  - a setting turns on a **different alert for critical events**, louder
    or otherwise distinct, with the same three settings of its own (R46).
    It is chosen from the generic `severity` only, never from the
    producer or the event's text.
  - by default a critical alert **sounds when the phone is on silent**
    but **not during do-not-disturb**; both are settings the owner can
    turn on or off (R46).
  - the general alert comes first: the critical alert reuses its sounds,
    settings screen and mechanism.
- **R47 was added by the maintainer on 2026-09-29**, after trying R45
  and R46 on the phone: SignalHub's vibration, two short buzzes and a
  longer one of about 0.6 s, is easy to miss without the sound. The
  owner chooses the vibration's **pattern** and **length** in the app, for
  the general alert and the critical alert each, as they choose the
  sound; it still never overrides the phone's silent mode, do-not-disturb
  or channel settings.
- **R48 was added by the maintainer on 2026-09-29**: the _Notifications_
  and _This device_ screens grew with R35 to R47 and are cluttered. The
  maintainer's answers, recorded here so no increment has to ask again:
  - one **Settings** screen replaces both, opened from a gear icon on the
    inbox; its settings sit in **folding groups** that show a one-line
    summary of their values when folded (chosen over plain folds, which
    hide the values, and over one sub-screen per group, which costs a
    tap for every change)
  - **Push filters** come first, then **Alert**, **Critical alert** and
    **This device**; the _Push notifications_ switch stays above them,
    always visible. "Push filters", not "Filters", so it is not confused
    with the inbox's _Filter_, which only changes what the inbox shows
  - device management (every device, _Connect a device_) stays **on its
    own screen**, reached from a row in Settings on an admin device: a
    long list with actions per device reads better on a screen of its own
  - _Disconnect this device_ moves from the inbox's menu into the _This
    device_ group
  - **no search for now**: with a handful of groups whose headers name
    their contents and whose summaries show their values, search would
    save little; it is reconsidered only if the folded screen still
    proves hard to use
  - after R47, so it arranges R47's new vibration settings too
- **R49 was added by the maintainer on 2026-09-29**: three Dependabot
  pull requests (the Maven compiler and Surefire plugins, and
  `actions/setup-java` 5 to 6) had waited since 2026-09-25, behind the
  queue. They land together in one pull request and one release, rather
  than three, each checked for breaking changes; the Dependabot pull
  requests are then closed as superseded.
- Notification grouping on the device was considered with them and left
  deferred: Android already bundles an app's notifications once several
  arrive, and grouping beyond that cannot be verified without a device.
- Java 25 and PostgreSQL 18 were numbered R20 and R21 before this queue was
  recorded. Renumbering milestones that never started costs no history and
  keeps the IDs in queue order; decisions D2 and D3 keep their names and
  remain the stable references.

### Release implications

Each row is one PR and one release, versioned by its title under the
post-1.0 rules of [development.md](development.md#versioning): `feat` minor,
every other type patch, `!` major. No version numbers are assigned in
advance; they follow from the queue.

| Item          | Expected release                                                                                                                                      | Why                                                                                                        |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| R20, R22, R24 | minor (`feat`)                                                                                                                                        | new artifacts and a new version surface; nothing existing changes                                          |
| R22a          | minor (`feat(client)`)                                                                                                                                | a new entry on an existing screen; no API change                                                           |
| R21           | minor (`feat`) if an install upgrading by the documented procedure keeps working; `!` with migration notes if it needs a new required setting or step | the deployment files and procedure are operator contract (Compatibility section of `docs/architecture.md`) |
| R23           | minor (`feat`)                                                                                                                                        | an addition to the client API; older apps ignore it                                                        |
| R25           | patch (`build`) unless it changes something the Compatibility section lists                                                                           | Java and the JVM are not part of the public contract                                                       |
| R26           | major (`!`) with migration notes, unless its implementation finds an upgrade that needs no operator action and the upgrade jobs prove it              | a dump and restore and a changed data directory mount are operator-breaking                                |
| R27           | patch (`fix(client)`)                                                                                                                                 | corrections to existing screens                                                                            |
| R28, R29      | minor (`feat`)                                                                                                                                        | new, additive capability; manual setup stays                                                               |
| R30           | minor (`feat`)                                                                                                                                        | a new optional event field; older clients ignore it                                                        |
| R31           | minor (`feat(client)`)                                                                                                                                | a new action in the app; no API change                                                                     |
| R32           | minor (`feat`)                                                                                                                                        | a new optional listing filter and app screens; older servers ignore the parameter                          |
| R33           | minor (`feat`)                                                                                                                                        | new response fields and a database migration that needs no operator action                                 |
| R34           | minor (`feat`)                                                                                                                                        | a new page on the host and a new push; no API, schema or configuration change                              |
| R35           | minor (`feat`)                                                                                                                                        | a new page on the host, new optional fields, a new management endpoint and a migration with no operator action |
| R36           | minor (`feat`)                                                                                                                                        | new client API endpoints, for admin clients only                                                           |
| R37           | minor (`feat(client)`)                                                                                                                                | a new screen in the app for admin devices; no API change                                                   |
| R38           | minor (`feat`)                                                                                                                                        | a new client API endpoint and app screen; pairing itself is unchanged                                      |
| R39           | patch (`chore`)                                                                                                                                       | removes a hidden redirect on the host; no public contract changes                                          |
| R40           | patch (`fix(client)`)                                                                                                                                 | a correction to an existing screen                                                                         |
| R41, R43      | minor (`feat`)                                                                                                                                        | new endpoints and page actions; a migration, if any, needs no operator action                              |
| R42, R44      | minor (`feat(client)`)                                                                                                                                | new actions in existing app screens; no API change                                                         |
| R45, R46      | minor (`feat(client)`)                                                                                                                                | new app settings; if a push payload change is needed, older apps keep working                              |
| R47           | minor (`feat(client)`)                                                                                                                                | new app settings; no API change                                                                            |
| R48           | minor (`feat(client)`)                                                                                                                                | a reorganized app screen; no API change                                                                    |
| R49           | patch (`build`)                                                                                                                                       | build and CI tool versions; nothing a user, producer or operator sees                                      |

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

Status: done (see section 3).

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

### R22a - The app's version and commit on the _This device_ screen

Status: done (see section 3).

Goal: the owner sees which SignalHub build the app on a phone is from the
app itself, without `adb` and without remembering how it was built. Release
identity and source provenance are shown separately: the release version
names the official artifact, the commit names the exact source.

Scope, client only:

- the _This device_ screen gets an entry of two lines:
  - an app built by a SignalHub release as its official artifact:
    "SignalHub X.Y.Z" and "Commit <short commit>"
  - any other build, including a local build from a release's tag:
    "SignalHub development build" and "Commit <short commit>"
  - `<short commit>` is the first 7 characters of the commit the app was
    built from, always shown, for release and development builds alike; a
    build that was not given its commit (such as a plain `flutter run`)
    shows "Commit unknown" rather than guess
- the version and the commit come in at build time as two separate values
  (for example two `--dart-define`s; the increment decides), never from the
  placeholder `version:` in `client/pubspec.yaml`, which stays a
  placeholder
- only the release's own app build sets the version, as only the release's
  image build sets the backend's (see the Version section of
  `docs/architecture.md`); it is not a setting for local builds, and the
  build commands in `client/README.md` never pass it, so a local build from
  the same tag never claims to be the release (the rules of
  [One version, many artifacts](#one-version-many-artifacts))
- the build commands in `client/README.md` pass the commit
  (`git rev-parse HEAD`), so every documented local build names its exact
  source; until R24 no release builds the app, so every installed app is a
  development build with its commit, and R24 makes the release's APK set
  its version through this same entry
- `client/README.md` and the Version section of `docs/architecture.md`
  describe the entry and both identities

Tests (widget tests against the fake server, as the other screens):

- a build given a version and a commit shows "SignalHub X.Y.Z" and
  "Commit <first 7 characters>"
- a build given only a commit shows "SignalHub development build" and
  "Commit <first 7 characters>"
- a build given neither shows "SignalHub development build" and
  "Commit unknown"
- the entry never shows the placeholder version of `client/pubspec.yaml`

Non-goals: the server's version on the screen (`/q/info` is on the host
only); a release APK (R24); any API change.

Exit criteria: an app built locally from a release's tag with the
documented command shows "SignalHub development build" and that tag's
short commit on the _This device_ screen of a real phone; the widget tests
above pass in CI.

### G3 - Decisions D5 and D6

Status: passed. The maintainer answered both on 2026-09-26 (after `v1.4.0`):
**D5 = a** (the backend serves the app's push configuration, R23) and
**D6 = one stable release signing key** (R24). The answers and the
requirements that came with them are in
[G3 answers](#g3-answers) below; the options as they were put to the
maintainer follow.

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
    change. _Recommended._
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

#### G3 answers

**D5: option a, backend-served push client configuration.** Intent: one
official released APK works with any SignalHub server. Requirements, binding
on R23 and R24:

- the backend serves only the client-safe configuration the app needs to
  initialise its push provider (for FCM, the Firebase project and app
  identifiers and client API configuration: identifiers, not authorization
  secrets)
- it never serves a server-side credential: not the service account key or
  any part of it, nor anything else able to send FCM messages
- provider-specific details stay at the integration edge; the core, the
  API shape and the schema stay provider-neutral
- the configuration is read through an authenticated client endpoint after
  setup (a client key), not a public unauthenticated one; real deployments
  serve it over HTTPS, as the rest of the client API
  ([deployment.md](deployment.md))
- the app validates the served configuration before initialising the push
  provider, and runs without push if it is missing or invalid
- registering a push token still needs an authenticated SignalHub client;
  a provider token alone is never SignalHub authentication
- local and development builds may keep compiled-in Firebase options as a
  development and fallback path
- the maintainer's personal Firebase options are never compiled into the
  released APK (that was option b, not chosen)
- if Firebase services beyond FCM are ever used, their security rules stay
  restrictive; the client API key is not a security boundary

**D6: one stable Android release signing key** for all official SignalHub
APKs. Requirements, binding on R24:

- the maintainer creates one release signing identity, reused for every
  official APK
- the keystore and its passwords are never committed; they live in GitHub
  Actions secrets (or equivalent CI secret storage), and the maintainer
  keeps a separate private offline backup
- the documentation states that losing the key prevents future updates
  over existing official installs: each device then uninstalls and sets up
  again
- the documentation states the one-time migration from a locally built
  (debug-signed) app to the first officially signed APK: uninstall, install
  the release APK, set up again with a client key
- creating the key and storing the secrets is the maintainer's step; R24
  names the secrets it needs, and if they are not present when R24 is
  otherwise ready, the run stops and asks for them rather than publishing an
  unsigned or debug-signed APK as a release

### R23 - Push configuration served by the backend

Status: complete, split in two, as its scope allowed. **R23a** (the
backend: the setting, `GET /api/v1/client/push-config`, the startup checks
and the end-to-end check) and **R23b** (the app: the three app bullets
below, its tests against the fake server, and `client/README.md`) are done
(see section 3). D5 chose **a** (G3, 2026-09-26); the
[G3 answers](#g3-answers) are binding on its scope.

Goal: an app that has no compiled-in push options gets them from its
server, so one released app works with any SignalHub server.

Scope:

- an operator setting names the app's push client options (for FCM, the
  Firebase options), validated at startup like the service account key;
  the startup summary says whether it is set
- a client key reads them through the client API (`GET /api/v1/client` or a
  sibling endpoint, the increment decides), in a provider-neutral shape: the
  provider name and an opaque map of options that the backend validates as
  JSON but does not interpret; no Firebase concept enters the domain;
  only client-safe values are served, never a server-side credential
- the app validates served options before initialising push, and runs
  without push when they are missing or invalid; setting a push target
  still needs the client key
- the app initialises push from served options when it has no compiled-in
  ones; compiled-in options keep working and take precedence
- tests against real PostgreSQL, the OpenAPI document, the app against its
  fake server, and the end-to-end job with served options

May be split into the backend and the app (as R11a and R11b were) if one PR
would be too large to review. Compatible (`feat`).

### R24 - Installable Android app in each release

Status: done (see section 3). D6 chose one stable release key (G3,
2026-09-26); the maintainer stored it as GitHub Actions secrets on
2026-09-27 (see [G3 answers](#g3-answers)).

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
- the release's app build sets the version and the commit, so the
  _This device_ entry R22a added shows "SignalHub X.Y.Z" and "Commit <short
  commit>"; a local build keeps showing "SignalHub development build" with
  its own commit
- a pull request's CI builds a release-mode APK (unsigned or with a
  throwaway key) so the release build cannot break unnoticed
- `client/README.md` and `docs/deployment.md`: download, verify the
  checksum, install, update by installing the next release's APK, and the
  one-time uninstall when replacing a locally built app, and that losing
  the release key prevents updates over official installs

Constraints and non-goals: no signing or Firebase secret in the repository,
logs or artifacts beyond what D5 allows; no AAB (no store distribution); no
iOS build (it needs the owner's Apple team: unchanged, built in Xcode).

Exit criteria: the APK of a release installs on a phone, sets up with a
client key, receives push as D5 decided, and reports that release and its
commit on the _This device_ screen.

### R25 - Java 25

Status: done (see section 3); decision D2.

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

Status: done (see section 3); decision D3.

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

Status: complete (see section 3).

Evidence: the non-blocking observations of the device review of `v0.27.3`.

Scope, client only:

- the event screen's read-state action has a visible label, not only an
  icon whose meaning is in a tooltip
- a row's time is readable in full at the default text size for every
  severity (on _High_ rows it was cut to `18:…` by the full date)
- when marking an event read on opening fails, the screen says so without
  blocking; the state shown stays the server's, as R18p made it
- while the server is unreachable, one message says so, instead of the
  connection error and the push-registration failure together; a
  push-registration failure is still shown when the server is reachable

Widget tests for each; no API change. Non-goals: the inbox features listed
under [Deferred candidates](#deferred-candidates).

### R28 - Pairing a device: the API

Status: complete (see section 3).

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

Status: complete (see section 3). The API it uses is described in
`docs/architecture.md#pairing` (R28).

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

### R30 - An event's link: the API and the SDK

Status: complete (see section 3). Added by the maintainer
(2026-09-27) from the deferred candidate "notification actions and deep
links", deliberately narrowed to one link.

Goal: a producer can attach one URL to an event that the owner opens with a
tap, without SignalHub interpreting it.

Scope:

- a new optional event field `link`, a single absolute `http` or `https`
  URL (the maximum length is the increment's to pick and document, around
  2000 characters), stored and returned as given and never fetched,
  followed or checked for reachability by the backend; other schemes are
  rejected with the usual violations
- it is generic: no producer-specific meaning, no label, no list of links,
  no action buttons; producer-specific URLs beyond the one the owner should
  open stay in metadata
- a Flyway migration adds a nullable column; existing events have no link
- idempotent publishing (R18g) compares `link` like any other field
- the Python SDK and the `signalhub` command accept it (`--link`)
- the integration examples that have a natural URL send it (the GitHub
  Actions example the run's URL); the others are unchanged
- the push payload is unchanged: the app reads the event by ID, as today
- tests against real PostgreSQL (valid, absent, too long, another scheme,
  idempotent replays), the OpenAPI document, the SDK and command tests, the
  examples' tests; `docs/architecture.md` (Events, Compatibility) and the
  SDK's README

Compatibility: additive (`feat`). Under the Compatibility section's rules a
producer that sends `link` to an older server gets `400`, so producers are
upgraded after the server; the release notes say so.

Non-goals: several links or labelled links, attachments or images,
notification action buttons, rendering metadata richer than today.

### R31 - Opening an event's link in the app

Status: complete (see section 3).

Scope, client only:

- the event screen shows the event's link, when it has one, as a clearly
  labelled action that opens it in the system browser (or the app the
  platform assigns to the URL), using one well-established Flutter package
  (`url_launcher`), justified in the PR
- tapping a notification still opens the event's screen, not the link: the
  owner sees what happened first and opens the link from there with one
  more tap, so a link never opens without the owner seeing it
- an inbox row may show that the event has a link (a small icon); opening
  it stays on the event screen
- a link that cannot be opened shows a message without leaving the screen
- the app ignores a `link` it cannot parse and shows the event as without
  one; an event from an older server has no `link` and looks as today
- widget and controller tests against the fake server; `client/README.md`
  and `docs/architecture.md` (Client application)

Non-goals: an in-app browser, opening the link directly from the
notification, notification action buttons.

Exit criteria: an event published with `--link` shows the link on its
screen, and one tap opens it.

### R32 - Inbox filters and an unread-only view

Status: complete (see section 3). Added by the maintainer
(2026-09-27) from the deferred candidates.

Goal: the owner narrows a long inbox by producer, category, severity and
unread, using the listing filters of R5.

Scope:

- the API: an optional listing filter on read state (for example
  `read=false`), combined with the others by AND, served by the partial
  unread index of R11a; tests against real PostgreSQL, including pagination
  with the filter and events marked read between pages
- the app: an unread-only toggle and filters for producer, category and
  severity on the inbox, applied on the server with the existing
  parameters; the active filters are visible and cleared with one action;
  the inbox paginates and refreshes as today with the filters applied
- the app remembers the filters on the device (not on the server, which has
  no per-client inbox state), or not at all; the increment decides and
  documents which
- an older server ignores the unknown read-state parameter (unknown query
  parameters are ignored), so it would return read events in the
  unread-only view; the app either checks the returned events' `readAt`
  and hides read ones, or documents that the view needs a server of this
  release or later; the increment decides
- the producers to choose from come from an existing source (the events
  already loaded, or a listing a client key may read); if none fits, the
  increment splits off the smallest API addition first, as its own row
- widget and controller tests; `docs/architecture.md` (Listing events,
  Client application) and `client/README.md`

May be split into the API and the app (as R11a and R11b were) if one PR
would be too large to review. Compatible (`feat`).

Non-goals: full-text search, filtering on `context`, metadata or text,
saved filters on the server, grouping, archive.

### R33 - Each client's last push result in the management API

Status: complete (see section 3). Added by the maintainer
(2026-09-27) from the deferred candidate "per-client delivery status".

Goal: the operator can see from the management API why a device got no
push, without reading metrics or logs.

Scope:

- for each client, the last successful push (when, and which event) and
  the last failed one (when, which event, and the provider's result, such
  as a permanent failure or an invalid target, without the token), and the
  number of pushes currently waiting for a retry
- kept as the latest result per client, overwritten by each attempt: not an
  attempt history (R13 found attempt records unjustified), and no
  dashboard
- recorded by the dispatcher and the retries after each send, without
  changing delivery semantics or ordering; a failure to record it never
  fails or repeats a push
- returned by `GET /api/v1/admin/clients` and `GET /api/v1/admin/clients/{id}`
  as new fields; nothing on the client API, and no app change
- a Flyway migration that needs no operator action; revoking a client keeps
  its last results
- tests against real PostgreSQL with the fake push provider (success,
  permanent failure, temporary failure then success, a retry pending,
  revoked client); the OpenAPI document; `docs/architecture.md` (Push
  dispatch, Client API) and `docs/development.md` (a curl example)

Compatible (`feat`): new response fields only.

Non-goals: showing it in the app (a later candidate), alerts on failures,
per-attempt records, metrics beyond those of R15a.

### R34 - The Connect page and the pairing notice

Status: complete (see section 3). Added by the maintainer (2026-09-27).

Goal: the operator makes a pairing code in a browser, and can send it to
someone else, without weakening what the management API protects.

Scope:

- a page on the backend's own port, not forwarded by the proxy, that
  creates a pairing with the admin token and shows it as a QR code until
  it expires; it copies the QR code as an image or the pairing link as
  text, and downloads the image
- the admin token is typed into the page and never stored; the page runs
  only its own scripts and cannot be framed or cached
- a push to the owner's other devices when a device pairs, so a code that
  leaked is noticed when it is used; best effort, never delaying or
  failing a pairing
- tests for the page, its headers and scripts, and the notice; the Compose
  smoke test checks the page is on the host and not through the proxy;
  docs for pairing, exposure and setup

Compatible (`feat`): no API, schema or configuration change.

Non-goals: a public page or a login, approving devices from a paired
device, a web client, rate limiting (still deferred).

### R35 - The admin page: every device, admin rights, renaming

Status: complete (see section 3). Added by the maintainer (2026-09-27),
after R34 (the Connect page and the pairing notice).

Goal: one page on the host where the operator sees every device and
manages it, and the only place where a device's admin rights are taken
away.

Scope:

- R34's Connect page becomes the **admin page**, on the backend's own port
  and never forwarded by the proxy, like the management API it calls;
  whether `/connect/` redirects to the new path or goes is the
  increment's to decide and document
- after the admin token, as in R34: every client, revoked or not, with its
  name, whether it is an admin, when it was created or revoked, whether it
  has a push target, and its last push results (R33)
- per device: **rename** it, so the owner can tell whose or what each
  device is; **make it an admin** or **take admin rights away**; **revoke**
  it, admins included, after a confirmation
- **add a device**: R34's pairing code, QR code, copy and download, with a
  choice to pair it as an admin
- the API behind it: an `admin` flag on clients and pairings (a Flyway
  migration; existing clients are not admins, so no operator action),
  returned with every client, including a client's own registration, so an
  app can tell it is an admin; an optional `admin` when registering a
  client or creating a pairing; a management endpoint that renames a
  client or sets its admin flag; a revoked client does not change (the
  increment picks the status and documents it)
- every change logged at `INFO` with client IDs only, as registering and
  revoking are; the pairing notice (R34) says when the new device is an
  admin
- tests against real PostgreSQL (the migration, the flag on every
  response, renaming, granting and taking admin rights, a revoked client,
  pairing as an admin), the OpenAPI document, the page and its headers,
  the Compose smoke test (the page on the host, `404` through the proxy);
  `docs/architecture.md` (Clients, Pairing, the page),
  `docs/deployment.md`, `docs/development.md`

Compatible (`feat`): new optional request fields, new response fields, a
new endpoint and a migration that needs no operator action.

Non-goals: anything in the app (R36, R37); a public page or a login other
than the admin token.

### R36 - Managing devices from an admin device: the API

Status: complete (see section 3). Added by the maintainer (2026-09-27).

Goal: a device the owner made an admin can manage the others through the
client API, with limits that keep a stolen admin device from taking over.

Scope:

- client API endpoints that answer only an **admin client's** key, and
  refuse every other client key the same way (the increment picks the
  status and documents it): list every device (as the admin page shows
  them, never a push token or key), **make a device an admin**, and
  **revoke a device that is not an admin**
- an admin device can do nothing to another admin, itself included: it
  cannot take admin rights away or revoke one; only the admin page (the
  admin token, R35) can
- under `/api/v1/client`, so the proxy forwards them like the rest of the
  client API; every change logged at `INFO` with client IDs only
- the owner's devices get a push, as R34's pairing notice, when a device is
  made an admin or revoked from a device, naming the device that did it
- tests against real PostgreSQL for every combination (an ordinary client,
  an admin, a revoked admin; the target an ordinary client, an admin,
  itself, revoked, unknown), the notices with the fake provider, the
  OpenAPI document; `docs/architecture.md` (Client API, and Security
  limitations: what a stolen admin key can do and how the operator
  recovers)

Compatible (`feat`): new endpoints; nothing existing changes.

Non-goals: renaming from a device (the admin page only), taking admin
rights away or revoking an admin from a device, the app (R37).

### R37 - Managing devices in the app

Status: complete (see section 3). Added by the maintainer (2026-09-27).

Scope:

- the app reads from its registration whether it is an admin; an admin
  device gets device management, as a tab of its own or from the _This
  device_ screen (the increment decides and says why); other devices see
  nothing new
- every device with its name, whether it is an admin, and which one is
  this device; **make an admin** and **revoke** (after a confirmation) on
  devices that are not admins, and neither on admins
- clear messages when this device lost its admin rights meanwhile, and
  nothing shown with a server older than R36
- controller and widget tests against the fake server; `client/README.md`

Compatible (`feat(client)`): no API change.

### R38 - Pairing codes from an admin device

Status: complete (see section 3). Added by the maintainer (2026-09-27) as
a later improvement, deliberately not released with R35 to R37.

Scope:

- an admin device creates a pairing code through the client API, as the
  admin page does; whether it may pair an admin directly is the
  increment's to decide (making a device an admin afterwards, R36, exists
  either way)
- in the app, _Connect a device_: the QR code with its countdown, and the
  pairing link to copy or share, as on the admin page
- the pairing notice (R34) names the device that created the code
- tests for the endpoint (admin only, as R36), the notice and the app
  screen; `docs/architecture.md` (Pairing), `client/README.md`

Compatible (`feat`): a new endpoint and app screen; redeeming is unchanged.

### R39 - Remove the /connect redirect

Status: complete (see section 3). Added by the maintainer (2026-09-27),
after R38.

Goal: the admin page has one address. The `/connect/` redirect that R35
kept for R34's bookmarks goes, so the path answers `404` on the backend's
own port, as it already did through the proxy.

Scope:

- remove the hidden `/connect` resource
- tests that `/connect`, `/connect/` and the old Connect page's script
  answer `404`, and that the OpenAPI document has no `/connect` path; the
  Compose smoke test expects `404` on the host as through the proxy
- `docs/architecture.md` (The admin page), `docs/deployment.md` (with an
  upgrade note to change bookmarks to `/admin/`), `docs/development.md`

Compatibility: not a breaking change. The redirect was never a public
contract: hidden from the OpenAPI document, not under `/api`, and never
forwarded by the proxy. No migration; bookmarks change to `/admin/`
(`chore`).

Non-goals: any other change to the admin page, the API or the app.

### R40 - The device list scrolls to its last device

Status: complete (see section 3). Added by the maintainer (2026-09-27),
from the functional review of `v2.11.1`.

Goal: an admin device sees every device in the app's device list (R37),
however long the list is.

Scope:

- when the list is longer than the screen, the last device is cut off and
  cannot be scrolled into view (found on a real phone); every device,
  the last one included, scrolls fully into view, clear of the navigation
  bar and system insets, with its actions reachable
- check the app's other long lists (the inbox, the preferences screens)
  for the same fault and fix it the same way where it occurs
- a widget test with more devices than fit on the screen that scrolls to
  the last one and finds it, and its actions, fully visible; it fails
  without the fix

Compatible (`fix(client)`): no API change.

Non-goals: any other change to the device list.

### R41 - Deleting revoked devices: the API and the admin page

Status: complete (see section 3). Added by the maintainer
(2026-09-27).

Goal: devices that were revoked, for example a phone paired again, can be
removed, so the list shows each device once.

Scope:

- a management endpoint (admin token) that deletes a **revoked** client;
  an active client is refused and does not change (the increment picks the
  statuses and documents them), an unknown ID is `404`
- the same for an admin device through the client API, under
  `/api/v1/client/devices`, admin only exactly as R36; a revoked admin
  may be deleted too, since it can no longer act
- deleting removes the client and everything that exists only for it (its
  read state, push results and retries, the unused pairing codes it
  created); events are never deleted. If a table references clients
  without `ON DELETE CASCADE`, a Flyway migration fixes it with no
  operator action
- the admin page: **Delete** on revoked devices only, after a
  confirmation; active devices have no delete, as before they must be
  revoked first
- logged at `INFO` with client IDs only, as revoking is; no push notice
  (deleting changes nothing a device can use)
- tests against real PostgreSQL (an active client refused, a revoked
  client and an admin deleted with their data, an unknown ID, an ordinary
  client key refused as R36), the OpenAPI document, the page;
  `docs/architecture.md` (Clients, the admin page, Client API, Security
  limitations: revoked clients can now be deleted, and the log is the
  record)

Compatible (`feat`): new endpoints; nothing existing changes.

Non-goals: the app (R42); deleting producers or producer keys; undoing a
delete.

### R42 - Deleting revoked devices in the app

Status: complete (see section 3). Added by the maintainer
(2026-09-27).

Scope:

- on an admin device's device list (R37), **Delete** on revoked devices
  only, after a confirmation; active devices have none
- the device leaves the list once deleted; clear messages when this
  device lost its admin rights meanwhile, and no delete shown with a
  server older than R41
- controller and widget tests against the fake server; `client/README.md`

Compatible (`feat(client)`): no API change.

### R43 - A used pairing code: the API and the admin page

Status: complete (see section 3). Added by the maintainer
(2026-09-27).

Goal: whoever shows a pairing code learns when it has been used, and is
ready to pair the next device.

Scope:

- a way for the admin page, and for an admin device about the codes it
  created (R38), to learn that a pairing it created was redeemed, and by
  which new device (its name), without ever exposing a code or a key: for
  example an ID in the `Pairing` response and a status endpoint in the
  management and client APIs that the page and the app poll while the
  code is shown; the increment decides the mechanism, and documents it.
  Redeeming a code today deletes its row, so the design must keep telling
  "used" from "expired" long enough for whoever shows the code
- the admin page: once the code is used, a toast says the device (its
  name) connected with the pairing code, the QR code and link disappear,
  and the page goes back to its first state (the device name and _Create
  pairing code_); an expired code is unchanged
- the client API part is admin only, as R38, and answers only about codes
  the calling device created
- tests against real PostgreSQL (used, expired, unknown, another device's
  code), the OpenAPI document, the page; `docs/architecture.md` (Pairing,
  the admin page, Client API)

Compatible (`feat`): new response fields and endpoints; redeeming is
unchanged.

Non-goals: the app (R44); pushing the news to the page (polling while a
code is shown is enough for one owner).

### R44 - A used pairing code in the app

Status: complete (see section 3). Added by the maintainer
(2026-09-27).

Scope:

- on _Connect a device_ (R38): once the code is used, a message says the
  device (its name) connected with the pairing code, the QR code and link
  disappear, and the screen goes back to its first state, ready for the
  next device; an expired code is unchanged
- clear messages when this device lost its admin rights meanwhile, and the
  screen as today with a server older than R43
- controller and widget tests against the fake server; `client/README.md`

Compatible (`feat(client)`): no API change.

### R45 - SignalHub's own alert: sounds, volume and vibration set in the app

Status: complete (see section 3). Added by the maintainer (2026-09-29).
The owner's check on a real phone is listed in the device review
(`scripts/device-review/README.md`, "Alert, by ear and by hand").

Goal: the owner tells a SignalHub push from any other app's notification
by ear and by feel, without looking at the phone, and sets how it sounds
and vibrates from the app.

Scope, the Android app:

- three or four notification sounds of SignalHub's own, short and
  distinct from Android's and Samsung's defaults, bundled with the app;
  their source and licence are recorded next to them, as the icon's are
  (`client/icon/`): original or public-domain (CC0) sounds, never ones
  taken from another product. One is the default
- a vibration pattern of SignalHub's own, distinct from the phone's
  default single buzz
- an _Alert_ section in the app's settings (the increment picks the
  screen, next to push preferences), with:
  - **Sound**: one of the bundled sounds, or none, each with a preview
  - **Volume**: the alert's loudness, a slider, with a preview
  - **Vibration**: its intensity, off and at least three steps (light,
    medium, strong); on a phone without vibration amplitude control the
    steps change the pattern's length instead
- these settings belong to this installation: they are stored on the
  device, not in the API, and survive app updates; every push shown by
  the system while the app is in the background or closed uses them; a
  push while the app is open keeps the in-app notice
- **the mechanism is the increment's to decide and document**, within
  these facts: Android fixes a notification channel's sound and vibration
  when it is created and has no per-channel volume, so the app either
  recreates its channel when a setting changes, or keeps the channel
  silent and plays the sound and vibration itself when a push arrives,
  or combines both. If it needs the backend to send pushes differently
  (for example data-only messages the app shows itself), that part is a
  compatible backend change, split into its own increment before this one
  if it is large: apps that do not know it keep showing notifications as
  today, and the push stays a generic signal (title, message, ID,
  category, severity), never a producer-specific one
- replacing the app's current `events` channel, if the mechanism needs a
  new one, is done once, still high importance so pushes keep popping up;
  the owner's own settings for the old channel are not carried over, and
  `client/README.md` and the release notes say so
- Android's own channel settings, do-not-disturb and the phone's silent
  mode still apply; the app never overrides them
- controller and widget tests for the settings (stored, restored,
  previewed) against the fake server, unit tests for the mapping from
  settings to what the platform is given, and a check in the device
  review (`scripts/device-review/`) for what only a phone can show;
  `client/README.md` (notifications); `docs/architecture.md` if the push
  payload changes

Compatible (`feat(client)`): no breaking API change; a server of any
version works with it, and a backend part, if any, is a compatible `feat`.

Non-goals: a different alert for critical events (R46); alerts per
category or producer, or for other severities (see
[Deferred candidates](#deferred-candidates)); sounds of the owner's own
from the phone's storage; iOS, where a custom sound must be named in the
push payload and iOS builds are not distributed (the Deferred candidates'
iOS row).

Exit criteria: on the owner's phone, with the release APK installed over
the previous one, a push that arrives while the app is in the background
or closed plays the chosen sound at the chosen volume and vibrates at the
chosen intensity; changing a setting changes the next push; a
notification from another app does not use them.

### R46 - A separate alert for critical events

Status: complete (see section 3). Added by the maintainer (2026-09-29).
The owner's check on a real phone is listed in the device review
(`scripts/device-review/README.md`, "Alert, by ear and by hand", items 8
to 11).

Goal: a `CRITICAL` event is unmistakable, louder or otherwise different
from every other SignalHub push.

Scope, the Android app:

- in the _Alert_ settings (R45), a switch **Different alert for critical
  events**, off by default
- when it is on, a `CRITICAL` push uses its own **Sound**, **Volume** and
  **Vibration**, set exactly as R45's (the same bundled sounds and
  steps); by default a more urgent sound, a higher volume and a stronger
  vibration than the general alert. Every other severity keeps the
  general alert
- when it is off, a `CRITICAL` push uses the general alert, as in R45
- chosen from the push's generic `severity` only (already in the push
  data), never from the producer, the category or the text; a severity
  the app does not know uses the general alert
- two more switches, for critical events only:
  - **Sound when the phone is on silent**, **on** by default: a critical
    alert plays its sound and vibration even when the phone's ringer is
    on silent or vibrate
  - **Sound during Do Not Disturb**, **off** by default: when off, a
    critical alert follows do-not-disturb like any notification; when
    on, it breaks through. Android lets an app through do-not-disturb
    only once the owner grants it Do Not Disturb access; the app says so
    and opens the system screen to grant it, and until access is given
    the switch stays off
  - with R45's mechanism, the increment decides how (for example
    playing the alert on the alarm stream, and reading the phone's
    current do-not-disturb state before playing) and documents it
- the general alert (R45) is unchanged: it always follows silent mode
  and do-not-disturb
- stored on the device like R45's settings
- the same kinds of tests as R45 (a critical and a normal push with the
  switch on and off, an unknown severity; silent mode and do-not-disturb
  with each switch on and off, and do-not-disturb access not granted),
  and device-review checks; `client/README.md`

Compatible (`feat(client)`): no API change beyond R45's.

Non-goals: sounding the general alert (R45) through silent mode or
do-not-disturb; a separate alert for `HIGH` or any other severity,
category or producer (see [Deferred candidates](#deferred-candidates)).

Exit criteria: on the owner's phone, with the switch on, a `CRITICAL`
push plays its own sound, volume and vibration and a `NORMAL` push plays
the general alert; with the switch off, both play the general alert. With
the default settings, a `CRITICAL` push sounds with the phone on silent
and stays quiet during do-not-disturb, and a `NORMAL` push is silent in
both; turning each switch around reverses its case.

### R47 - The alert's vibration pattern and length, set in the app

Status: complete (see section 3). Added by the maintainer (2026-09-29),
after trying R45 and R46 on the phone. The owner's check on a real phone
is listed in the device review (`scripts/device-review/README.md`,
"Alert, by ear and by hand", items 12 to 15).

Goal: a SignalHub push is felt, not only heard. SignalHub's vibration
(R45), two short buzzes and a longer one of about 0.6 s, is easy to miss
without the sound; the owner chooses a pattern and a length that they
notice.

Scope, the Android app:

- in the _Alert_ settings (R45), next to **Vibration** (its intensity),
  two more settings, for the general alert and, when **Different alert
  for critical events** (R46) is on, for the critical alert each:
  - **Pattern**: three or four vibration patterns of SignalHub's own,
    clearly different from each other and from the phone's single buzz,
    for example today's (the default for the general alert, so nothing
    changes until the owner chooses), a steady long buzz, a heartbeat
    and a rapid pulse; each with a preview
  - **Length**: how long the vibration lasts, at least three steps (for
    example short, about 0.6 s as today; medium, about 2 s; long, about
    5 s), by repeating the pattern, never longer than about 10 s; with a
    preview
- the critical alert's defaults are more noticeable than the general
  alert's (for example the rapid pulse, long); the general alert's
  defaults keep today's vibration
- the intensity steps (R45) keep working with every pattern and length;
  on a phone without amplitude control the steps still change the
  buzzes' length, as R45 decided, and the length setting still applies
- stored on the device like R45's and R46's settings, surviving app
  updates; settings saved by R46 are kept, and the new settings start at
  their defaults
- the alert still never overrides the phone: silent mode, vibrate,
  do-not-disturb and the channel's settings apply exactly as in R45 and
  R46 (a critical alert vibrates through silent or do-not-disturb only
  when its R46 switch says so); opening the notification or the app
  stops a long vibration
- the same kinds of tests as R45 and R46 (the mapping from settings to
  the platform's timings and amplitudes, controller and widget tests
  against the fake server and `FakeAlertPlatform`), the device review's
  alert checks extended to the chosen pattern and length where `adb` can
  see them, and the by-hand list for what only the owner can feel;
  `client/README.md` (Alert)

Compatible (`feat(client)`): no API change.

Non-goals: patterns drawn or recorded by the owner; a vibration per
category, producer or other severity (see
[Deferred candidates](#deferred-candidates)); a vibration that repeats
until the notification is opened; iOS.

Exit criteria: on the owner's phone, with the release APK installed over
the previous one, each pattern and length feels as chosen, in the
previews and on a push with the app in the background or closed, for the
general alert and the critical alert each; the defaults leave the
general alert's vibration as it was.

### R48 - One Settings screen, in folding groups

Status: complete (see section 3). Added by the maintainer (2026-09-29).
The exit criteria need the owner's phone and are left to the next device
review (`scripts/device-review/`), which follows the new screen.

Goal: the app's settings are easy to find and take little space; the
owner sees what each group is set to without opening it.

Scope, the app:

- one **Settings** screen replaces _Notifications_ and _This device_; the
  inbox's menu, left with nothing else, becomes a **gear icon** in the
  inbox's top bar that opens it
- at the top, always visible, the **Push notifications** switch
- below it, **folding groups**, in this order, each with a header that,
  folded, shows a one-line summary of its current values (for example
  _Normal and up · Info, Completed muted · all producers_, _Signal · 80 %
  · Medium_):
  - **Push filters**: minimum severity, categories, producers
  - **Alert**: sound, volume, vibration and R47's pattern and length,
    with their previews
  - **Critical alert**: R46's switch and its own sound, volume, vibration,
    pattern and length, and the silent and do-not-disturb switches
  - **This device**: its name and server, push status, version and
    commit, and **Disconnect this device** (with its confirmation), moved
    from the inbox's menu
- on an admin device, a **Devices** row in Settings (with a summary such
  as _7 devices · 2 admins_) opens device management (R37, R42) and
  _Connect a device_ (R38, R44) on a screen of their own, as today
- groups start folded; the app remembers, on the device, which groups
  the owner left open
- while push is off, Push filters, Alert and Critical alert are shown
  greyed with a line saying they apply once push is on, and can still be
  changed
- every setting keeps its behaviour, storage and previews: nothing moves
  to or from the API, and no stored setting is lost
- the device review (`scripts/device-review/`) follows the new screen and
  labels in the same change, so the next review still runs
- widget tests: each group folded and unfolded, its summary for
  representative values, the remembered open groups, greyed groups while
  push is off, the Devices row only on an admin device, Disconnect from
  Settings, the gear icon; `client/README.md`

Compatible (`feat(client)`): no API change.

Non-goals: a search of the settings (reconsidered only if the folded
screen still proves hard to use); new settings; changes to device
management itself; the inbox's _Filter_.

Exit criteria: on the owner's phone, Settings opens from the gear icon
with every group folded and its summary correct; each group unfolds to
its settings, which work as before; Devices opens device management on
an admin device; Disconnect works from _This device_.

### R49 - The pending Dependabot updates

Status: complete (see section 3). Added by the maintainer (2026-09-29).

Goal: the dependency updates Dependabot proposed are applied, verified
and released, and no Dependabot pull request is left waiting.

Scope:

- the updates of the Dependabot pull requests open when this increment
  starts, applied together on one branch from the latest `main`. On
  2026-09-29 they were:
  - #6: `org.apache.maven.plugins:maven-compiler-plugin` 3.15.0 to 3.16.0
    (`backend/pom.xml`)
  - #8: `org.apache.maven.plugins:maven-surefire-plugin` 3.5.6 to 3.6.0
    (`backend/pom.xml`)
  - #9: `actions/setup-java` 5 to 6, in every workflow that uses it
    (`ci.yml`, `release.yml`)
- for each, the upstream release notes read for breaking changes that
  touch SignalHub (the Java 25 build with `-Xlint:all` and SpotBugs, the
  test run against real PostgreSQL, the release workflow's Android build),
  with any needed adjustment made in the same pull request and noted in
  its description; an update that cannot be taken safely is left out and
  the reason recorded, never forced
- the full validation: `./mvnw verify`, and CI green on every job,
  including the release-image and upgrade jobs; a check that fails for a
  reason outside the change (a registry or network hiccup) is re-run, not
  worked around
- once merged, each Dependabot pull request it covers is closed with a
  comment naming the pull request that superseded it, if Dependabot has
  not closed it already
- a Dependabot pull request opened meanwhile is included if it is of the
  same kind (build and CI tooling) and its CI is green; one that changes
  runtime dependencies of the backend, the app or the SDK is left for its
  own increment

Compatible (`build`, patch): build and CI tool versions only; nothing a
user, producer or operator sees changes.

Non-goals: changing Dependabot's configuration or schedule; updating
dependencies Dependabot has not proposed; runtime dependency upgrades.

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

| Candidate                                                                                                 | Why not now                                                                                                                           | What would justify it                                                                                                 |
| --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| Each client's push status in the app                                                                      | The management API shows it from R33                                                                                                  | The owner needs it on the phone, not from the management API.                                                         |
| Full-text search                                                                                          | No need shown; R5 ruled it out as premature                                                                                           | Filters prove insufficient. PostgreSQL's own search, no search engine.                                                |
| Unread navigation, grouping in the inbox, further bulk actions, archive or clear                          | _Mark all as read_ and retention cover today's use                                                                                    | Usage evidence from the owner.                                                                                        |
| Quiet hours or schedule-based suppression                                                                 | Pause and the phone's own do-not-disturb and channel settings cover it (R12a found it unjustified)                                    | A need the phone cannot meet, such as suppression by severity at night. Never a rules engine.                         |
| Alerts per category or producer, or for severities other than critical                                    | R45 tells SignalHub apart and R46 sets critical events apart, which is what the owner asked for                                       | The owner needs to tell such pushes apart by ear. Only generic fields, never a producer's name or text.               |
| Notification grouping on the device                                                                       | Event volume is low, and Android already bundles an app's notifications once several arrive; considered with R30 to R33 and left here | Bursts of pushes that Android's own bundling does not make readable, seen on a device.                                |
| Rate limiting and brute-force resistance                                                                  | Keys and pairing codes make guessing infeasible; the management API is not forwarded (`docs/architecture.md#security-limitations`)    | Abusive or heavy traffic seen in logs or metrics; the proxy is the first place to limit.                              |
| Key expiry, key scopes, a separate management port                                                        | One owner; rotation and revocation exist; the documented mitigations hold                                                             | A producer that must be restricted, or managing from another host.                                                    |
| Richer metadata rendering, notification action buttons, several or labelled links, attachments and images | Metadata is opaque by principle; actions need generic semantics in the event schema; one link per event is scheduled as R30 and R31   | Several unrelated producers needing the same generic capability, with a design that keeps the core producer-agnostic. |
| Web or desktop client                                                                                     | The app covers the owner's phones                                                                                                     | The owner needs the inbox away from the phone; the API assumes no platform, so no backend change.                     |
| Distributed iOS builds, APNs directly                                                                     | iOS builds need the owner's Apple team; FCM already relays to APNs                                                                    | An iOS user of released builds.                                                                                       |
| The SDK on PyPI                                                                                           | The release's wheel (R22) and installing from a tag suffice                                                                           | Producers that cannot install from GitHub.                                                                            |
| SDKs in more languages                                                                                    | `curl`, the command and Python cover the examples' producers                                                                          | A producer ecosystem where plain HTTP is a real burden.                                                               |

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
(section 4) is authoritative. R34 (the Connect page and the pairing
notice), R35 (the admin page), R36 (managing devices from an admin
device: the API), R37 (managing devices in the app), R38 (pairing codes
from an admin device), R39 (removing the /connect redirect), R40 (the
device list scrolls to its last device), R41 (deleting revoked devices:
the API and the admin page), R42 (deleting revoked devices in the app),
R43 (a used pairing code: the API and the admin page), R44 (a used
pairing code in the app), R45 (SignalHub's own alert, set in the app), R46
(a separate alert for critical events), R47 (the alert's vibration
pattern and length, set in the app), R48 (one Settings screen, in
folding groups) and R49 (the pending Dependabot updates) are done. **The
queue is empty: nothing further is scheduled.** A new item is added only by
the maintainer, in a reviewed pull request; the deferred candidates of
section 5 are not started without that.

The orchestrator must first inspect `main`, releases and open pull requests to confirm this remains true.
