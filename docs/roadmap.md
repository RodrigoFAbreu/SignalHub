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
event needs the owner's credential), R18c (one error format), R18d (the
end-to-end test), R18e (the fresh-install deployment test), R18f (the
compatibility policy and enum evolution), R18g (idempotent publishing),
R18h (the upgrade from an older release), R18i (pre-1.0 cleanup: retries
in the examples and stale statements), R18j (the v1.0 readiness review) and
R18k (events visible in listing order, closing O1), R18l (dispatcher
tests, closing O2), R18m (Dependabot coverage, closing O3), R18n (admin
listings in an items envelope, decision D1), R18o (pop-up notifications,
app icon and refresh on return) and R18p (the read-state toggle on the
event screen) are complete (see section 3). What remains
is the queue in [Remaining work to v1.0.0 and after](#remaining-work-to-v100-and-after)
below.

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
| Release automation | Reviewed; sound | No PR title can produce `1.0.0` (`scripts/release/release.py` turns a major bump into a minor one below 1.0). Promotion is decision D4: not yet. |
| End-to-end, fresh-install and upgrade tests | Done | R18d, R18e, R18h. |
| Real-device push | Done on Android; its defect fixed in R18p | Verified on the maintainer's Android phone with their Firebase project at `v0.27.0` (R18o): a functional review passed its 19 checks (foreground, background, killed app and cold start, pop-up over another app, read state, push preferences, idempotent publishing, backend down and restarted, phone offline). It found that the event screen only offered *Mark as unread*, fixed in R18p (the action now follows the event's read state; verifying it on the device is the maintainer's, with R18q's review). iOS with APNs does not block 1.0 unless another issue requires it. |
| Device-review tooling | Open (R18q) | The review's script exists only on the maintainer's machine; R18q keeps it in the repository. |
| Maintainer usability review | Open, maintainer (G1) | After R18p to R18r: the maintainer uses the app and signs off. |

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
  JRE (PR #7) and a Maven image on JDK 26 (PR #4). The stack is Java 21 LTS
  and CI tests only on 21; moving to 25 is a stack change, and building on
  a non-LTS JDK 26 would differ from CI. **Decided: keep Java 21 for 1.0;
  Java 25 is a dedicated maintenance milestone after 1.0.**
- **D3 - PostgreSQL 18.** Dependabot proposes `postgres:18-alpine` (PR #5).
  A major version needs a dump and restore of existing data and a changed
  data directory mount in `compose.yaml`, so it is a breaking operator
  change with migration notes, not a routine update. **Decided: keep
  PostgreSQL 17 for 1.0; PostgreSQL 18 is a dedicated maintenance milestone
  after 1.0.**
- **D4 - promotion to `v1.0.0`.** The maintainer approves the public
  contract as stable. The release is then a PR, titled with `!`, that
  removes the pre-1.0 rule from `scripts/release/release.py` and its tests
  and updates `docs/development.md#versioning` and `CLAUDE.md`. **Decided:
  not yet.** The maintainer first verifies push on a real device (Android
  with FCM is enough), and `v1.0.0` needs their explicit approval after that
  test. Push was verified on Android at `v0.27.0` (R18o); the approval now
  follows the queue below and is still not given.

### Remaining work to v1.0.0 and after

Recorded after the real-device functional review of `v0.27.0`. This table
is the queue of the remaining work, in order; each row is one increment
(one PR, one release) or one human gate. Nothing below may be reordered by
an orchestrator: Java 25 and PostgreSQL 18 never move ahead of `v1.0.0`.

| Order | Item | Kind | Status |
|---|---|---|---|
| 1 | R18p - Read-state toggle on the event screen | Increment (`fix(client)`) | Done (see section 3) |
| 2 | R18q - Device-review tooling in the repository | Increment (`test`) | **Next** |
| 3 | R18r - Stale branch cleanup | Repository hygiene (no PR, no release) | Queued |
| - | Clearing local device-test data | Documentation | Done with this queue ([development.md](development.md#clearing-local-test-data)) |
| 4 | G1 - Maintainer usability review and sign-off | Human gate | Waiting for 1 to 3 |
| 5 | G2 - Explicit approval of `v1.0.0` (decision D4) | Human gate | Not given |
| 6 | R19 - `v1.0.0` | Increment (`!`, the release) | Blocked by G2 |
| 7 | R20 - Java 25 (decision D2) | Increment | Blocked until `v1.0.0` is released |
| 8 | R21 - PostgreSQL 18 (decision D3) | Increment | Blocked until R20 is merged |

How an autonomous run uses it:

1. Confirm from `main`, the releases and the open PRs that the table is
   current (an item's PR may have merged without its row being updated;
   then update the row first, in the next PR).
2. Take the first row whose status is not *Done*. If it is a human gate, or
   *Blocked*, stop and report: nothing after it may start.
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

After R18p to R18r, the maintainer uses the app on their device and signs
off, or reports defects; each defect becomes a new row before G1.
Automation never marks G1 done.

#### G2 and R19 - `v1.0.0`

Decision D4. Only after G1 and the maintainer's explicit approval, stated
in a PR or issue by the maintainer, does the release PR (R19, titled with
`!`) remove the pre-1.0 rule from `scripts/release/release.py` and its
tests and update `docs/development.md#versioning` and `CLAUDE.md`.

#### R20 - Java 25, after `v1.0.0`

Decision D2: its own milestone and PR. Build and runtime images, CI and the
docs move to Java 25 LTS together; the Dependabot PRs that raise the JDK
images are closed or replaced by it.

#### R21 - PostgreSQL 18, after R20

Decision D3: its own milestone and PR, separate from R20. A breaking
operator change (`!`) with migration notes: dump and restore, and the
changed data directory mount in `compose.yaml`; the tests' PostgreSQL image
follows Compose's. After `v1.0.0`, `!` makes it a major release.

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

The queue in [Remaining work to v1.0.0 and after](#remaining-work-to-v100-and-after)
(section 4) is authoritative. After the functional review of `v0.27.0`, the
expected next increment is:

**R18q - Device-review tooling in the repository** (R18p is done), then
R18r (stale branch cleanup). Then the maintainer's usability
review (G1) and explicit approval (G2) gate `v1.0.0` (R19); Java 25 (R20)
and PostgreSQL 18 (R21) follow `v1.0.0`, each in its own PR. `v1.0.0` is
never released without the maintainer's explicit approval.

The orchestrator must first inspect `main`, releases and open pull requests to confirm this remains true.
