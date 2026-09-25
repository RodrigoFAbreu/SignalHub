# Architecture

> Status: direction, not implementation. No runtime component exists yet. This
> document defines boundaries and vocabulary. Concrete schemas, APIs, and
> technology details are decided in the PRs that implement them, and this
> document is updated in the same PRs.

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
- Repository layout for multiple components (expected: one top-level directory
  per component).
