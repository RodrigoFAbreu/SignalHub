# Architecture

> Status: mostly direction. Only the backend runtime foundation exists (see
> [Backend](#backend)). It does not ingest events yet. This document defines
> boundaries and vocabulary. Concrete schemas, APIs, and technology details are
> decided in the PRs that implement them, and this document is updated in the
> same PRs.

## Purpose

SignalHub accepts generic events from any producer, persists them, and delivers
notifications about them to the owner's mobile device. It is a personal
platform: one owner, many producers.

## System boundaries

```
 Producers                     SignalHub                         Owner
┌──────────────┐          ┌──────────────────────┐          ┌──────────────┐
│ agents       │          │  Backend (API)       │  push    │ Android app  │
│ CI systems   │  HTTPS   │   ├ ingest + validate│ ───────▶ │  (FCM token) │
│ monitoring   │ ───────▶ │   ├ persist          │   FCM    │              │
│ homelab      │  events  │   └ dispatch         │          │  reads events│
│ scripts      │          │  PostgreSQL          │ ◀─────── │  via API     │
└──────────────┘          └──────────────────────┘   HTTPS  └──────────────┘
        ▲
        │ optional
  Python SDK / CLI
```

**Inside SignalHub:** the backend API, its database, delivery dispatch, the
mobile app, and the producer SDK/CLI.

**Outside SignalHub:** producers and their logic, Firebase Cloud Messaging as
a transport, and the host that runs the Docker deployment.

## Flow

1. **Publish.** A producer sends an event to the backend over HTTPS with a
   producer credential. The SDK/CLI is a convenience. The HTTP API is the
   contract, and any producer can call it directly.
2. **Ingest.** The backend authenticates the producer, validates the event
   against the generic schema, and stores it durably *before* acknowledging it.
   An accepted event is never lost because a later delivery step fails.
3. **Dispatch.** Delivery decisions use only generic event fields (for example
   severity). Dispatch sends a push through FCM to registered devices. Delivery
   is at-least-once, and the app must tolerate duplicates (for example by event
   id).
4. **Consume.** The Android app shows the notification and fetches event
   details from the backend API. A push is a signal to look, not the system of
   record.

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
| Backend | Python, FastAPI | Producer API, validation, persistence, dispatch, app-facing API |
| Database | PostgreSQL | System of record for events, producers, devices, delivery state |
| Push | Firebase Cloud Messaging | Transport to devices only, carrying minimal payloads |
| Mobile app | Kotlin, Jetpack Compose | Device registration, notifications, event browsing |
| Producer SDK/CLI | Python | Thin client over the public HTTP API |
| Deployment | Docker, Docker Compose | Reproducible self-hosted deployment |

## Backend

Implemented: the runtime foundation. That is configuration, database access,
migrations, health endpoints, and the Docker deployment. There is no event
API and no domain table yet.

### Layout

Each component has its own top-level directory. The backend is in `backend/`:

| Path | Contents |
|---|---|
| `src/signalhub/main.py` | `create_app()` application factory |
| `src/signalhub/config.py` | `Settings`: typed configuration from the environment |
| `src/signalhub/db.py` | Engine, ORM `Base`, request-scoped `DbSession` |
| `src/signalhub/health.py` | Health endpoints |
| `migrations/` | Alembic environment and revisions |
| `tests/` | pytest suite, run against real PostgreSQL |
| `Dockerfile` | Production image |

`compose.yaml` at the repository root runs the backend with PostgreSQL.

### Configuration

All configuration comes from environment variables with the `SIGNALHUB_`
prefix. It is validated at startup, and the process exits if it is invalid.

| Variable | Required | Description |
|---|---|---|
| `SIGNALHUB_DATABASE_URL` | yes | PostgreSQL URL with the `postgresql+psycopg://` scheme. It has no default, because it contains the database password. The password is kept out of logs, reprs, and validation errors. |

Docker Compose builds this URL from `POSTGRES_PASSWORD` in `.env` (see
`.env.example`).

### HTTP endpoints

Health endpoints are unversioned operational endpoints, not part of the
producer API. The producer API will be versioned under its own path prefix
when it is built.

| Endpoint | Meaning | Responses |
|---|---|---|
| `GET /health/live` | The process is serving requests. Checks no dependencies. | `200 {"status": "ok"}` |
| `GET /health/ready` | The service can do useful work. It runs `SELECT 1` on the database. | `200 {"status": "ok", "checks": {"database": "ok"}}`, or `503 {"status": "unavailable", "checks": {"database": "unavailable"}}` |

A readiness failure is logged as one warning line. The response never includes
connection details. A database connection attempt times out after 5 seconds.
FastAPI also serves its generated OpenAPI schema at `/openapi.json` and
interactive docs at `/docs`.

### Startup and database access

- Startup does not connect to the database. The API starts, and reports
  liveness, while the database is down. Readiness reports the outage and
  recovers without a restart when the database returns. Pooled connections
  are checked before use.
- Request handlers get a session through the `DbSession` dependency. Each
  request is one transaction: it commits when the handler returns and rolls
  back when it raises. The commit completes **before** the response is sent,
  so a failed commit can never be acknowledged as a success. This is the
  mechanism behind *durability first*.
- ORM models subclass `signalhub.db.Base`. Its metadata uses a fixed
  constraint naming convention, so migrations stay deterministic.

### Migrations

Alembic manages the schema. Migrations do not run on application startup.
They are an explicit step, `alembic upgrade head`, which the Compose `migrate`
service runs before the API starts. CI applies every migration to a fresh
database, checks that the models match the migrations, and downgrades again.
There are no revisions yet.

## Cross-cutting principles

- **Durability first:** persist, then acknowledge, then deliver.
- **Idempotency:** producers may retry, so ingestion should support
  deduplication.
- **Secrets from the environment:** credentials (producer tokens, FCM service
  account, database password) come from runtime configuration, never from the
  repository.
- **Versioned contracts:** the producer API and event schema are public
  contracts. Breaking them is a breaking change under the release policy in
  [development.md](development.md).

## Open questions

These are deferred until the relevant implementation work:

- Producer authentication model (per-producer tokens vs. signed requests).
- Event retention and pruning policy.
- Routing and filtering rules: which events trigger a push, quiet hours.
