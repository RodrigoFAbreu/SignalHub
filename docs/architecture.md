# Architecture

> Status: partly direction. Implemented so far: the backend runtime foundation
> (see [Backend platform](#backend-platform)) and generic event ingestion (see
> [Events](#events)). Authentication, dispatch, and clients do not exist yet.
> This document defines boundaries, vocabulary, and the chosen technology.
> Concrete schemas, APIs, and implementation details are decided in the PRs
> that implement them, and this document is updated in the same PRs.

## Purpose

SignalHub accepts generic events from any producer, persists them, and delivers
notifications about them to the owner's devices. It is a personal platform:
one owner, many producers, and one or more clients.

## System boundaries

```
 Producers                     SignalHub                         Owner
┌──────────────┐          ┌──────────────────────┐          ┌──────────────┐
│ agents       │          │  Backend (Quarkus)   │  push    │ Clients      │
│ CI systems   │  HTTPS   │   ├ ingest + validate│ ───────▶ │ (mobile, web,│
│ monitoring   │ ───────▶ │   ├ persist          │ provider │  CLI, ...)   │
│ homelab      │  events  │   └ dispatch         │          │  reads events│
│ scripts      │          │  PostgreSQL          │ ◀─────── │  via API     │
└──────────────┘          └──────────────────────┘   HTTPS  └──────────────┘
        ▲
        │ optional
   SDK / CLI
```

**Inside SignalHub:** the backend API, its database, delivery dispatch, the
client applications, and the optional producer SDK/CLI.

**Outside SignalHub:** producers and their logic, push providers (such as
Firebase Cloud Messaging) as transports, and the host that runs the Docker
deployment.

## Flow

1. **Publish.** A producer sends an event to the backend over HTTPS with a
   producer credential. The SDK/CLI is a convenience. The HTTP API is the
   contract, and any producer can call it directly.
2. **Ingest.** The backend authenticates the producer, validates the event
   against the generic schema, and stores it durably *before* acknowledging it.
   An accepted event is never lost because a later delivery step fails.
3. **Dispatch.** Delivery decisions use only generic event fields (for example
   severity). Dispatch sends a push through a push provider to registered
   devices. Delivery is at-least-once, and clients must tolerate duplicates
   (for example by event id).
4. **Consume.** A client shows the notification and fetches event details from
   the backend API. A push is a signal to look, not the system of record.
   Clients without push (for example a CLI) read the same API directly.

## Generic events and producer metadata

The central rule: **SignalHub core understands only generic event semantics.**

- **Generic fields** have one meaning across all producers, and core behaviour
  may depend on them. The current set is defined in [Events](#events).
- **Producer metadata** is an opaque, producer-defined structured payload
  attached to an event. SignalHub stores it, returns it, and may display it
  generically (for example as key/value pairs). SignalHub never branches on its
  contents.

If a producer needs behaviour that SignalHub does not support, the answer is a
new *generic* capability that any producer could use, never a special case.
Core code must not reference specific producers such as agent frameworks, CI
vendors, or monitoring tools by name. Producer-specific adapters, if ever
needed, live outside the core and speak the generic API.

## Events

> Status: implemented. Producers can publish and read events. There is no
> producer authentication yet, so Compose publishes the API on localhost only.

An event is a generic record of something that happened in a producer. The
model is deliberately small: fields that every producer understands the same
way, plus opaque metadata for everything else.

| Field | Type | Required | Set by | Meaning |
|---|---|---|---|---|
| `id` | UUID | always present | server | Canonical event ID. |
| `source` | string, 1–100 | yes | producer | Who published the event, e.g. `ci/build-runner`. |
| `context` | string, 1–200 | no | producer | Project or context, e.g. a repository, host, or job. |
| `category` | enum | yes | producer | What the event means for the owner (below). |
| `severity` | enum | yes | producer | How urgently the owner should notice it (below). |
| `title` | string, 1–200, not blank | yes | producer | Short human-readable summary. |
| `message` | string, 0–4000 | no | producer | Longer human-readable text. |
| `metadata` | JSON object, ≤ 16 KiB | no | producer | Opaque producer data (below). |
| `occurredAt` | timestamp | no | producer | When the underlying occurrence happened, per the producer. |
| `createdAt` | timestamp | always present | server | When SignalHub stored the event. |

`source` and `context` are identifiers: letters, digits, and `. _ : / -`,
starting with a letter or digit. Text fields must not contain NUL (U+0000)
characters, which PostgreSQL cannot store.

### Category and severity

The two enums carry all the generic meaning that later routing and
notification rules may depend on. They are small on purpose: a producer maps
its own states onto them, and details go in metadata.

| Category | Meaning |
|---|---|
| `ACTION_REQUIRED` | The owner must act: approve, answer, or decide. |
| `BLOCKED` | Work cannot continue until something external changes. |
| `COMPLETED` | Work finished. |
| `INFO` | Informational. No action expected. |

| Severity | Meaning |
|---|---|
| `LOW` | Can wait. |
| `NORMAL` | The default for most events. |
| `HIGH` | Should be seen soon. |
| `CRITICAL` | Needs immediate attention. |

Values are uppercase and exact. Both fields are required, so no producer
relies on an implicit default; making one optional later is a compatible
change, but the reverse is not. Adding a value is a contract change, since
existing clients may not recognise it, and needs a migration for the database
check constraint.

### IDs

The server generates every ID as a UUIDv7 (RFC 9562): globally unique without
coordination, safe to expose, and roughly ordered by creation time, which
keeps primary-key inserts cheap. Producers cannot supply `id` (or
`createdAt`): unknown fields are rejected, so a producer that tries gets a 400
rather than a silently different ID.

Idempotent publishing is not implemented yet. When it is needed, it will be an
additive, optional producer-supplied key (with a unique constraint scoped to
the source), not a producer-controlled canonical ID.

### Timestamps

- All timestamps are ISO-8601 strings with an explicit UTC offset, stored as
  PostgreSQL `timestamptz` and returned in UTC (`Z`) with up to microsecond
  precision. Finer precision is truncated.
- `createdAt` is canonical: the server's clock when it stored the event.
  Ordering and retention will use it.
- `occurredAt` is producer context. SignalHub stores and returns it but does
  not trust it for ordering: producer clocks may be wrong, and events may be
  published late. A timestamp without an offset (`2026-09-25T14:03:00`) is
  rejected because it is ambiguous, as are epoch numbers. The year must have
  four digits (0001–9999). The offset the producer sent is not kept; only the
  instant is.

### Metadata

`metadata` is an optional JSON object for producer-specific data, for example a
CI run number, a workflow step, or a link. SignalHub stores it as PostgreSQL
`jsonb` and returns it, but never reads, validates, or branches on its
contents. An absent or `null` value is stored and returned as `{}`.

- It must be a JSON object (not an array or scalar), so clients can always
  display it generically as key/value pairs.
- It is at most 16 KiB as compact UTF-8 JSON. SignalHub is a notification
  system, not a document store; put large payloads behind a link.
- Values round-trip as JSON values: strings are unchanged, and numbers keep
  their exact value (never rounded through a floating-point type), though
  trailing fractional zeros may be dropped (`1.10` becomes `1.1`). Object key order, whitespace, and duplicate keys (the last
  one wins) follow `jsonb` semantics and are not preserved.
- It must not contain NUL characters or numbers outside PostgreSQL's numeric
  range.

### HTTP API

| Method and path | Result |
|---|---|
| `POST /api/v1/events` | Validates and stores an event. `201 Created` with the canonical event and a `Location` header. |
| `GET /api/v1/events/{id}` | `200` with the event, or `404`. |

The event is committed to PostgreSQL before `201` is returned. Errors:

- `400` with a JSON body `{"title", "status", "violations": [{"field", "message"}]}`
  for malformed JSON, unknown fields, wrong JSON types (values are never
  coerced, e.g. `42` is not a string), and failed validation. `field` is the
  JSON path, or empty for the whole body.
- `404` with the same body shape (no violations) for an unknown event ID. A
  malformed ID is also `404`, without a body.
- `413` for request bodies over 64 KiB, and `415` for non-JSON bodies.

The OpenAPI document at `/q/openapi` is the reference for the request and
response schemas, with examples. See
[development.md](development.md#events-api) for curl examples.

### Schema

`V1__create_events.sql` creates the `events` table. Check constraints repeat
the API's invariants (lengths, non-blank title, enum values, metadata is an
object), so the database stays valid even when something other than the API
writes to it. There are no secondary indexes: the only query is by primary key.
Indexes arrive with the features that query by other columns.

## Likely components

| Component | Direction | Responsibility |
|---|---|---|
| Backend | Java 21, Quarkus (see [Backend platform](#backend-platform)) | Producer API, validation, persistence, dispatch, client-facing API |
| Database | PostgreSQL | System of record for events, producers, devices, delivery state |
| Push | A push provider, likely Firebase Cloud Messaging | Transport to devices only, carrying minimal payloads |
| Clients | Undecided (Android, iOS, web, CLI, ...) | Device registration, notifications, event browsing |
| Producer SDK/CLI | Optional, for example Python | Thin client over the public HTTP API |
| Deployment | Docker, Docker Compose | Reproducible self-hosted deployment |

## Backend platform

> Status: runtime foundation implemented in `backend/` (service, database
> connectivity, migrations, health, OpenAPI, container). No product API yet.

The backend is a single Quarkus service in JVM mode, backed by one PostgreSQL
database. That is enough for a personal notification service and leaves room
to grow. Distributed infrastructure (message brokers, caches, Kubernetes) is
out of scope until a concrete need appears that PostgreSQL and one service
cannot meet.

| Concern | Choice |
|---|---|
| Language and runtime | Java 21 (LTS) |
| Framework | Quarkus |
| HTTP API | Quarkus REST (RESTEasy Reactive), JSON |
| Persistence | Hibernate ORM with Panache over PostgreSQL |
| Schema migrations | Flyway |
| Input validation | Jakarta Validation |
| API description | SmallRye OpenAPI |
| Health checks | SmallRye Health |
| Tests | JUnit 5, RestAssured, real PostgreSQL |
| Packaging | Docker image, run with Docker Compose |

Implementation expectations:

- **Stable HTTP contract.** Producers and clients depend only on the HTTP API
  and its OpenAPI description, never on Java types or backend internals. The
  producer API is versioned in its path (for example `/api/v1/...`).
- **Client-agnostic API.** Client-facing endpoints and device registration are
  generic. The push provider is a replaceable outbound boundary that core
  logic does not depend on.
- **Panache where it helps.** Use Panache for simple entities and queries.
  Use plain Hibernate ORM or SQL when a query needs precise control. Keep
  persistence details out of the HTTP layer.
- **Durability.** An event is committed to PostgreSQL before the API
  acknowledges it. Push dispatch happens after the commit and tolerates
  retries.
- **Schema changes only through Flyway.** Migrations are versioned, reviewed,
  and part of the database contract. Hibernate never generates or alters the
  schema, and tests build their schema with the same Flyway migrations.
- **Configuration from the environment.** Use Quarkus configuration
  (`application.properties` with environment-variable overrides). Commit only
  non-secret defaults. Credentials come from the runtime environment.
- **Health.** Liveness and readiness through SmallRye Health. Readiness
  includes database connectivity.
- **Tests against real PostgreSQL**, for example with Quarkus Dev Services or
  a CI service container. HTTP behaviour is tested with RestAssured.

### Backend implementation decisions

- **Build tool: Maven** with the committed wrapper (`backend/mvnw`). It is
  Quarkus's primary build tool: its guides, extension tooling, and platform BOM
  assume it, and a single-module service needs nothing Gradle adds. The
  Quarkus version comes from the `io.quarkus.platform:quarkus-bom` import.
- **Layout:** one Maven module in `backend/`, one top-level directory per
  component. Java code lives under the `io.github.rodrigofabreu.signalhub`
  package. Packages are split by feature as features arrive, not by
  speculative technical layer.
- **Formatting:** google-java-format through the Spotless Maven plugin.
  It is fully automatic (`./mvnw spotless:apply`), so style is never debated
  in review.
- **Static analysis:** SpotBugs on production bytecode, plus
  `javac -Xlint:all` with warnings as errors. Both run in `./mvnw verify`
  alongside the tests, which is exactly what CI runs.
- **Packaging:** Quarkus fast-jar in JVM mode. `backend/Dockerfile` builds it
  in a Maven stage and runs it on an Eclipse Temurin 21 JRE as a non-root
  user, with base images pinned by digest. Heap is sized from the container
  limit (`-XX:MaxRAMPercentage=75`). Native images are out of scope.
- **Configuration:** `application.properties` holds non-secret defaults.
  Dev and test get PostgreSQL from Quarkus Dev Services. The `prod` profile
  reads `SIGNALHUB_DB_URL`, `SIGNALHUB_DB_USERNAME`, and
  `SIGNALHUB_DB_PASSWORD`, and the service refuses to start without a
  database URL, because Quarkus would otherwise deactivate the datasource
  and report ready without a database.
- **Schema:** Flyway runs at startup in every profile from
  `classpath:db/migration`, with migration naming validated. Hibernate's
  schema management is `none`. Tables are listed in
  `backend/src/main/resources/db/migration/README.md`.
- **Endpoints:** Quarkus's standard management paths under `/q/`:
  `/q/health/live` (liveness, no dependency checks), `/q/health/ready`
  (readiness, includes the PostgreSQL connection check), and `/q/openapi`.
  The product API lives under `/api/v1/...`, so the two never collide.
- **Code layout:** the event feature lives in the `event` package: the
  resource (HTTP), request and response records (API models), a service
  (transactions and mapping), and the JPA entity with a Panache repository
  (persistence). The entity is package-private and never serialized.
  Cross-cutting HTTP concerns (strict JSON reading, error bodies) live in
  `api`.
- **Deployment:** `compose.yaml` runs the backend and PostgreSQL 17 with a
  named volume. The backend starts after the database is healthy and is
  itself health-checked through readiness.

## Cross-cutting principles

- **Durability first:** persist, then acknowledge, then deliver.
- **Idempotency:** producers may retry, so ingestion should support
  deduplication. Not implemented yet; see [IDs](#ids).
- **Secrets from the environment:** credentials (producer tokens, push-provider
  credentials, database password) come from runtime configuration, never from
  the repository.
- **Versioned contracts:** the producer API and event schema are public
  contracts. Breaking them is a breaking change under the release policy in
  [development.md](development.md).

## Open questions

These are deferred until the relevant implementation work:

- Producer authentication model (per-producer tokens vs. signed requests).
- Event retention and pruning policy.
- Routing and filtering rules: which events trigger a push, quiet hours.
- Client platforms: which clients (Android, iOS, web, CLI) are built first,
  and their technology.
