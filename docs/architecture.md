# Architecture

> Status: mostly direction. The backend runtime foundation exists (see
> [Backend platform](#backend-platform)); no product feature does yet. This
> document defines boundaries, vocabulary, and the chosen technology. Concrete
> schemas, APIs, and implementation details are decided in the PRs that
> implement them, and this document is updated in the same PRs.

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
  may depend on them. Likely candidates: event id, producer identity, timestamp,
  title, body/summary, severity or priority, an optional link, and an optional
  grouping/deduplication key. The exact set is decided when the event API is
  built.
- **Producer metadata** is an opaque, producer-defined structured payload
  attached to an event. SignalHub stores it, returns it, and may display it
  generically (for example as key/value pairs). SignalHub never branches on its
  contents.

If a producer needs behaviour that SignalHub does not support, the answer is a
new *generic* capability that any producer could use, never a special case.
Core code must not reference specific producers such as agent frameworks, CI
vendors, or monitoring tools by name. Producer-specific adapters, if ever
needed, live outside the core and speak the generic API.

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
  schema management is `none`. There are no tables yet: the first feature that
  stores data adds the first migration.
- **Endpoints:** Quarkus's standard management paths under `/q/`:
  `/q/health/live` (liveness, no dependency checks), `/q/health/ready`
  (readiness, includes the PostgreSQL connection check), and `/q/openapi`.
  The product API will live under `/api/v1/...`, so the two never collide.
- **Deployment:** `compose.yaml` runs the backend and PostgreSQL 17 with a
  named volume. The backend starts after the database is healthy and is
  itself health-checked through readiness.

## Cross-cutting principles

- **Durability first:** persist, then acknowledge, then deliver.
- **Idempotency:** producers may retry, so ingestion should support
  deduplication.
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
