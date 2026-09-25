# Architecture

> Status: partly direction. Implemented so far: the backend runtime foundation
> (see [Backend platform](#backend-platform)), generic event ingestion and the
> event listing (see [Events](#events)), producer authentication (see
> [Producers and authentication](#producers-and-authentication)), and client
> registration with client keys and push targets (see [Clients](#clients)),
> the push-provider boundary with a Firebase Cloud Messaging provider, and
> event-triggered push dispatch (see [Push delivery](#push-delivery)). No
> client application exists yet.
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

> Status: implemented. Registered producers publish events with an API key;
> the owner's clients list them with client keys (the operator may also use
> the admin token); reading one event by ID needs
> no credential yet (see [Security limitations](#security-limitations)), so
> Compose publishes the API on localhost only.

An event is a generic record of something that happened in a producer. The
model is deliberately small: fields that every producer understands the same
way, plus opaque metadata for everything else.

| Field | Type | Required | Set by | Meaning |
|---|---|---|---|---|
| `id` | UUID | always present | server | Canonical event ID. |
| `producer` | object `{id, name}` | always present | server | The producer that published the event, from its API key. |
| `context` | string, 1–200 | no | producer | Project or context, e.g. a repository, host, or job. |
| `category` | enum | yes | producer | What the event means for the owner (below). |
| `severity` | enum | yes | producer | How urgently the owner should notice it (below). |
| `title` | string, 1–200, not blank | yes | producer | Short human-readable summary. |
| `message` | string, 0–4000 | no | producer | Longer human-readable text. |
| `metadata` | JSON object, ≤ 16 KiB | no | producer | Opaque producer data (below). |
| `occurredAt` | timestamp | no | producer | When the underlying occurrence happened, per the producer. |
| `createdAt` | timestamp | always present | server | When SignalHub stored the event. |

`context` is an identifier: letters, digits, and `. _ : / -`, starting with a
letter or digit. Text fields must not contain NUL (U+0000) characters, which
PostgreSQL cannot store.

Who published an event is never part of the request body. The producer comes
only from the API key that authenticated the request (see
[Producers and authentication](#producers-and-authentication)), so the body
cannot contradict it: a body with `source`, `producer`, or any other unknown
field is rejected with `400`. Before producer authentication existed, events
carried a producer-supplied `source`; it was removed rather than kept as an
unverified second identity.

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
rather than a silently different ID. The same holds for the producer.

Idempotent publishing is not implemented yet. When it is needed, it will be an
additive, optional producer-supplied key (with a unique constraint scoped to
the producer), not a producer-controlled canonical ID.

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
| `POST /api/v1/events` | Requires a producer API key. Validates and stores an event bound to that producer. `201 Created` with the canonical event and a `Location` header. |
| `GET /api/v1/events` | Requires a client key or the admin token. One page of events, newest first, optionally filtered. See [Listing events](#listing-events). |
| `GET /api/v1/events/{id}` | `200` with the event, or `404`. No credential needed yet. |

The event is committed to PostgreSQL before `201` is returned. Errors:

- `401` when publishing without a valid producer API key. Authentication runs
  before the body is read, so an unauthenticated request gets `401` whatever
  its body contains. See [Authentication errors](#authentication-errors).

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

### Listing events

`GET /api/v1/events` is the inbox: what a client shows the owner without
knowing any event ID in advance.

**Credential.** It requires one of the owner's credentials: a client key (see
[Clients](#clients)), which is how client applications read, or the admin
token (see [Producer management](#producer-management)), which lets the
operator read with curl. Without a configured admin token only client keys
are accepted; the listing never answers `404`. Anything else, including a
producer key, gets the same `401` as every credential failure: producers
publish, they do not read other producers' events.

**Order.** Events are ordered by `createdAt`, newest first, then by `id`
(descending) among events stored in the same microsecond, so the order is
total and stable. `occurredAt` is not used for ordering (see
[Timestamps](#timestamps)).

**Filters.** All optional, and combined with AND. Repeating a parameter
matches any of its values (OR), e.g. `severity=HIGH&severity=CRITICAL`.

| Parameter | Meaning |
|---|---|
| `producerId` | Events of this producer (canonical ID). Repeatable. |
| `category` | Events with this category. Repeatable. |
| `severity` | Events with this severity. Repeatable. |
| `createdFrom` | Events with `createdAt` at or after this time (inclusive). |
| `createdBefore` | Events with `createdAt` before this time (exclusive). |

Timestamps follow the same rules as in request bodies: ISO-8601 with an
explicit offset. In a URL, write a `+` offset as `%2B`, or use `Z`. Filters
use only generic fields; there is no filtering on `context`, metadata, or
text, and no full-text search.

**Pagination.** Cursor-based (keyset), not page numbers or offsets:

```
{"items": [ ...events, newest first... ], "nextCursor": "MToxNzkw..."}
```

- `limit` sets the page size, 1–100, default 50.
- `nextCursor` is an opaque string, or `null` on the last page. To read the
  next page, repeat the request with the same filters and `cursor` set to it.
- A cursor marks the position after the last event of its page. Events
  published after the first page was read never shift or repeat entries on
  later pages; they appear when the listing is started again from the first
  page. Every page costs the same however deep it is.
- Changing the filters while keeping a cursor is allowed: the result is the
  events after that position that match the new filters.
- Cursors are versioned internally; a client must not construct or parse
  them, only pass them back.

Invalid parameters get `400` with one violation per problem, naming the
parameter in `field` (e.g. `limit`, `category`, `cursor`). An unknown
producer ID is not an error; it just matches no events. Unknown query
parameters are ignored.

### Schema

`V1__create_events.sql` creates the `events` table. Check constraints repeat
the API's invariants (lengths, non-blank title, enum values, metadata is an
object), so the database stays valid even when something other than the API
writes to it. `V2__add_producer_authentication.sql` replaces the `source`
column with `producer_id`, a foreign key to `producers`.
`V3__index_events_for_listing.sql` adds the listing's indexes:
`(created_at, id)` for the inbox and its category, severity and time filters,
and `(producer_id, created_at, id)` for the producer filter. Category and
severity have only four values each, so they are filtered while reading the
ordered index rather than indexed on their own.

## Producers and authentication

> Status: implemented. Producers authenticate with API keys. There is no
> owner, user, or client authentication yet.

A **producer** is a registered external system that publishes events: a CI
pipeline, an agent, a monitor, a script. SignalHub treats every producer the
same way. A producer has:

| Field | Meaning |
|---|---|
| `id` | Server-generated canonical ID (UUIDv7). |
| `name` | Unique, stable machine-readable name, shown on its events. Letters, digits and `. _ : / -`, starting with a letter or digit, at most 100 characters. Chosen at registration and never changed. |
| `createdAt` | When it was registered. |
| `disabledAt` | Set while the producer is disabled; `null` while enabled. |
| `keys` | Its API keys: ID, `createdAt`, and `revokedAt` (`null` while valid). |

A producer can hold several keys at once, which is what makes rotation
gap-free. Producers are never deleted, so their events keep their attribution.

### API keys

The server generates every key. Keys look like this:

```
shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_Zt1v...(43 characters)
└─┬─┘ └──────────────┬───────────────┘ └──────────┬──────────┘
format       key ID (public)              secret (256 bits)
```

- `shpk1_` names the format ("SignalHub producer key", version 1). It makes
  keys recognizable to secret scanners and in accidental pastes, and lets a
  future format coexist with this one.
- The **key ID** is the primary key of the key's record, as 32 lowercase hex
  digits (a random UUIDv4). It is not secret. It selects the one stored
  record to check, so authentication is a single primary-key lookup whatever
  the number of keys.
- The **secret** is 32 bytes from `java.security.SecureRandom`, encoded as
  unpadded base64url (43 characters, which may include `-` and `_`).

A key is 82 characters. Treat the whole string as the credential.

**Storage.** Only `SHA-256(key)` is stored (`producer_api_keys.key_hash`); the
key itself is never stored, logged, or returned after the response that
issued it. SHA-256 is the right tool here, not a password hash such as bcrypt
or Argon2: those slow down guessing of low-entropy human passwords, but a
256-bit random secret cannot be guessed at any speed, so a slow hash would
only add CPU cost to every published event. A leaked database therefore does
not reveal usable keys. There is no reversible encryption and no server-side
key material to manage.

**Verification.** The server parses the key ID from the presented key, loads
that one record together with its producer, and compares hashes with
`MessageDigest.isEqual` (constant time). An unknown key ID is compared against
a dummy hash, so it does the same work as a wrong secret. The key must not be
revoked and its producer must be enabled.

### Authentication

Producers send the key as a standard bearer credential (RFC 6750):

```http
POST /api/v1/events
Authorization: Bearer shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_...
```

The scheme name is case-insensitive; exactly one space separates it from the
key. The authenticated producer becomes the event's `producer`. Only
`POST /api/v1/events` requires a key.

#### Authentication errors

Every failure is `401 Unauthorized` with a
`WWW-Authenticate: Bearer realm="signalhub"` header and the same body:

```json
{"title": "Unauthorized", "status": 401, "violations": []}
```

This covers a missing `Authorization` header, another scheme (such as
`Basic`), a malformed key, an unknown key ID, a wrong secret, a revoked key,
and a disabled producer. A disabled producer gets `401` rather than `403` on
purpose: the response never tells a caller whether a key ID exists, is
revoked, or belongs to a disabled producer. The operator sees the reason in
the backend's `DEBUG` log (see [Logging](#logging)).

### Producer management

The operator manages producers through a small HTTP API under
`/api/v1/admin/producers`, protected by a separate **admin token**:

- The token comes only from the `SIGNALHUB_ADMIN_TOKEN` environment variable
  and must be at least 32 characters (`openssl rand -hex 32`); a shorter one
  stops the service at startup. Only its SHA-256 is kept in memory, and
  comparison is constant-time.
- Without the variable the management API is **disabled**: every path answers
  `404`, with or without credentials. Producers with existing keys keep
  publishing. This is the default in every environment.
- With the variable set, requests without the exact token get the same `401`
  as producer failures. Producer keys are not admin tokens and vice versa.
- The same token also manages clients (see [Clients](#clients)) and may read
  the event listing (see [Listing events](#listing-events)): in a
  single-owner service the operator is the owner.

This is a bootstrap mechanism for a single-owner, self-hosted service, not a
user or role system. See [development.md](development.md#producers-and-api-keys)
for curl examples.

| Method and path | Result |
|---|---|
| `POST /api/v1/admin/producers` | Registers a producer (`{"name": ...}`) and issues its first key. `201` with the producer, `keyId`, and `apiKey`; `409` if the name is taken. |
| `GET /api/v1/admin/producers` | All producers with their key records, by name. |
| `GET /api/v1/admin/producers/{id}` | One producer with its key records. |
| `POST /api/v1/admin/producers/{id}/keys` | Issues an additional key. `201` with `keyId` and `apiKey`. |
| `POST /api/v1/admin/producers/{id}/keys/{keyId}/revoke` | Revokes a key, immediately and permanently. Idempotent. |
| `POST /api/v1/admin/producers/{id}/disable` | Disables the producer: none of its keys authenticate. Idempotent. Events are kept. |
| `POST /api/v1/admin/producers/{id}/enable` | Re-enables it: its unrevoked keys work again. |

Unknown producer or key IDs get `404`, as does a key ID used with another
producer's path.

### Key lifecycle

1. **Issue.** Registering a producer issues its first key. The response is the
   only time the key is shown; store it in the producer's secret store. A lost
   key cannot be recovered, only replaced.
2. **Rotate.** Issue a new key, switch the producer to it, then revoke the old
   one. Both keys work in between, so there is no downtime.
3. **Revoke.** A revoked key stops authenticating on the next request.
   Revocation cannot be undone; issue a new key instead.
4. **Disable.** Disabling the producer blocks all its keys at once without
   revoking them, for example while investigating a misbehaving producer.
   Enabling it restores the keys that were not revoked.

Existing events are never changed by any of these.

### Schema

`V2__add_producer_authentication.sql` creates:

- `producers`: `id`, unique `name` (1–100 characters), `created_at`,
  `disabled_at`.
- `producer_api_keys`: `id` (the key ID), `producer_id`, `key_hash` (exactly 32
  bytes), `created_at`, `revoked_at`. Indexed by `producer_id` for listing a
  producer's keys; authentication uses the primary key.

It also binds existing events: each distinct `source` becomes an enabled
producer with that name and no keys, dated from its oldest event, and the
events reference it. Those events were published before authentication, so
their attribution was never verified. The operator can issue keys to such a
producer to keep using its name.

### Logging

Credentials never reach the logs. The backend logs producer registration,
key issuance and revocation, and disabling and enabling at `INFO` with
producer and key IDs only. Rejected credentials are logged at `DEBUG` with the
reason and, when the key is well formed, its key ID, never the key, the
`Authorization` header, the admin token, or a hash. `IssuedApiKey`, the only
type that holds a key, omits it from `toString()`.

### Security limitations

This version protects publishing. It does not yet:

- **Authenticate readers by ID.** `GET /api/v1/events/{id}` needs no
  credential. Event IDs are unguessable UUIDv7s returned only to the
  publishing producer and to the owner's listing, but anyone who learns one
  and can reach the API can read the event. Listing events requires a client
  key or the admin token. Requiring one here too is a breaking change,
  deferred to a deliberate contract decision.
- **Terminate TLS.** Keys and the admin token travel as bearer credentials, so
  any non-local access needs a TLS reverse proxy. Compose publishes the API on
  `127.0.0.1` only.
- **Rate-limit** authentication attempts. Guessing is infeasible (256-bit
  secrets), but a flood of requests still costs a database lookup each.
- **Separate the management API** onto its own port or network. It is
  protected by the admin token and disabled by default; for the tightest
  setup, set `SIGNALHUB_ADMIN_TOKEN` only while managing producers or
  clients, and restart without it afterwards; clients keep reading with
  their own keys.
- **Expire keys** automatically. Keys are valid until revoked.
- **Scope keys**: every valid key may publish any event as its producer.

## Clients

> Status: implemented. Clients are registered, authenticate with client keys,
> read events, and store a push target. No push is sent yet.

A **client** is one installation of a SignalHub client application on one of
the owner's devices: a phone app, a desktop app, a CLI. SignalHub has one
owner, so a client is not a user account: it is a credential for reading the
owner's events plus, optionally, where to push notifications. The model is
the same for every platform.

| Field | Meaning |
|---|---|
| `id` | Server-generated canonical ID (UUIDv7). |
| `name` | Human-readable label chosen by the owner, e.g. `Pixel 8`. 1–100 characters, not blank. Need not be unique. |
| `createdAt` | When it was registered. |
| `revokedAt` | Set once the client is revoked; `null` while it is active. |
| `pushTarget` | `{provider, updatedAt}`, or `null` if the client has no push target. |

### Client keys

The operator registers a client through the management API, which issues its
**client key**, shown only in that response:

```
shck1_01a0da2c1f3e7a518d0c6b1f2e3d4c5b_Zt1v...(43 characters)
```

Client keys follow the producer key design (see [API keys](#api-keys)): a
format prefix (`shck1_`, "SignalHub client key", version 1, distinct from
producer keys so neither can be mistaken for the other), the client ID as 32
hex digits, and a 256-bit secret. Only `SHA-256(key)` is stored
(`clients.key_hash`), verification is one primary-key lookup with a
constant-time comparison, and every failure is the same `401` (see
[Authentication errors](#authentication-errors)).

A client has exactly one key for its lifetime. A key belongs to one
installation, so rotating it means registering the installation again as a
new client and revoking the old one. Revocation is permanent and immediate.

**What a client key may do:** read the event listing, and read and change its
own registration under `/api/v1/client`. It cannot publish, manage producers
or other clients, or see push targets of other clients.

### Push targets

A **push target** is where pushes for a client go: the name of a push
provider and the token that provider issued to the installation.

- `provider` is a lowercase identifier (letters, digits and `. _ -`, starting
  with a letter or digit, at most 50 characters), such as `fcm`. SignalHub
  does not keep a list of providers yet; delivery (a later release) decides
  which ones it supports.
- `token` is opaque, 1–4096 characters, without NUL. SignalHub stores it and
  hands it to the provider, but never parses it, and never returns it: it
  addresses a device, so it is write-only in the API and never logged.
- The client sets it with `PUT /api/v1/client/push-target` whenever its
  provider issues a new token, and removes it with `DELETE`. A client has at
  most one push target.
- **One installation, one client.** A push target belongs to at most one
  client: setting it takes it away from any other client that had it (same
  provider and token). An app that is reinstalled and registered again
  therefore never receives each push twice, even before the old client is
  revoked.
- Revoking a client removes its push target, and a revoked client can never
  get one; the database enforces both.

### Client API

| Method and path | Credential | Result |
|---|---|---|
| `POST /api/v1/admin/clients` | admin token | Registers a client (`{"name": ...}`). `201` with the client and `clientKey`. |
| `GET /api/v1/admin/clients` | admin token | All clients, oldest first. |
| `GET /api/v1/admin/clients/{id}` | admin token | One client. |
| `POST /api/v1/admin/clients/{id}/revoke` | admin token | Revokes the client and removes its push target. Idempotent. |
| `GET /api/v1/client` | client key | The calling client's registration. |
| `PUT /api/v1/client/push-target` | client key | Sets the push target (`{"provider", "token"}`). `200` with the client. |
| `DELETE /api/v1/client/push-target` | client key | Removes the push target. Idempotent. `200` with the client. |

The management paths behave like producer management: `404` for every path
while no admin token is configured, `404` for unknown IDs, and `400` for
invalid bodies with the usual violations. See
[development.md](development.md#clients) for curl examples.

### Schema

`V4__create_clients.sql` creates `clients`: `id`, `name`, `key_hash` (exactly
32 bytes), `created_at`, `revoked_at`, and `push_provider`, `push_token`,
`push_updated_at`, which are either all set or all `null`. A check constraint
forbids a push target on a revoked client. Changes to one client lock its
row, so a revocation and a concurrent push-target update apply in order
rather than one overwriting the other.

### Logging

Registration, revocation and push-target changes are logged at `INFO` with
the client ID and provider name only; never the key, its hash, or the push
token. Rejected client keys are logged at `DEBUG` like producer keys.

## Push delivery

> Status: the provider boundary, the `fcm` provider and event-triggered
> dispatch are implemented and tested with fakes. Retries are roadmap R13.

Delivery code asks for a push to one client and never sees a concrete
provider. Everything provider-specific stays behind one small interface, so
adding a provider (Firebase Cloud Messaging first) touches only the edge.

```
 caller ──deliver(clientId, message)──▶ PushDelivery ──send(token, message)──▶ PushProvider "fcm", ...
                                          │  reads the client's push target
                                          └─ removes it on INVALID_TARGET
```

- **`PushMessage`** is the provider-neutral content: a title, an optional
  body, and string key/value data for the client app (for example the event
  ID to open). Each provider translates it into its own format.
- **`PushProvider`** is the boundary: a `name()` that matches the `provider`
  of push targets (see [Push targets](#push-targets)), and
  `send(token, message)`, which returns a classified outcome.
- **`PushDelivery.deliver(clientId, message)`** looks up the client's push
  target, picks the provider by name, sends outside any database transaction,
  and acts on the outcome.

| Outcome | Meaning | What SignalHub does |
|---|---|---|
| `DELIVERED` | The provider accepted the message. | Nothing more. |
| `INVALID_TARGET` | The target no longer exists (e.g. the app was uninstalled). | Removes the client's push target, unless the client registered a new one meanwhile. |
| `TRANSIENT_FAILURE` | Unavailable, rate-limited, timed out; may succeed later. | Logs a warning and keeps the target. |
| `PERMANENT_FAILURE` | Retrying will not help, but the target is not condemned (e.g. a rejected payload or a misconfigured provider). | Logs a warning and keeps the target. |

Delivery also reports `NO_TARGET` (unknown or revoked client, or no push
target) and `UNSUPPORTED_PROVIDER` (no active provider has the target's
name; the target is kept, since the provider may be configured later). An
exception thrown by a provider counts as a transient failure.

**Configuration boundary.** Providers are CDI beans in the backend. A
provider that is not configured (for example without credentials) must not be
an active bean; the active set is logged at startup, and two providers with
one name, or a name no push target could carry, stop startup. Credentials are
each provider's own configuration, read from the environment.

### Firebase Cloud Messaging

The `fcm` provider sends through the FCM HTTP v1 API
(`POST https://fcm.googleapis.com/v1/projects/{project}/messages:send`). It is
active only when `SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE` names a Firebase service
account key file (JSON, as the Firebase console issues it). The project comes
from that file. A missing, unreadable or malformed file, or one that is not a
service account key, stops startup; the message names the problem, never the
key.

- **Authentication.** The provider signs a JWT with the service account key
  and exchanges it at the file's `token_uri` for an OAuth 2.0 access token
  (scope `firebase.messaging`, RFC 7523). The token is cached and renewed five
  minutes before it expires. Only the JDK is used (HTTP client, RSA
  signature), so no Google SDK is a dependency.
- **Message.** A `PushMessage` becomes an FCM notification message: the title
  and optional body as `notification`, the data as `data`, addressed to the
  push target's token. Nothing FCM-specific leaks out of the provider.
- **Outcomes.**

  | FCM answer | Outcome |
  |---|---|
  | `2xx` | `DELIVERED` |
  | error code `UNREGISTERED` (the app was uninstalled or the token expired) | `INVALID_TARGET`: the target is removed |
  | `401` (access token rejected) | `TRANSIENT_FAILURE`; the next send gets a new token |
  | `429`, `5xx`, connection errors, timeouts (10 s) | `TRANSIENT_FAILURE` |
  | other `4xx`, such as `INVALID_ARGUMENT` or `SENDER_ID_MISMATCH` | `PERMANENT_FAILURE`: the target is kept |
  | token endpoint `4xx` (key or account rejected) | `PERMANENT_FAILURE` |
  | token endpoint `429`, `5xx` or unusable answer | `TRANSIENT_FAILURE` |

  Only `UNREGISTERED` condemns a target: FCM reports `INVALID_ARGUMENT` for a
  bad payload too, and `SENDER_ID_MISMATCH` also when SignalHub is configured
  with the wrong project, and neither should wipe the owner's registrations.
  Outcome details hold the HTTP status and FCM's error code only, never the
  response text, which may quote the token.
- **Network.** Outbound HTTPS to `oauth2.googleapis.com` and
  `fcm.googleapis.com`. The JVM's standard proxy settings (`https.proxyHost`)
  apply. `signalhub.push.fcm.api-url` overrides the API base URL, which tests
  use to point at a local fake.

The file is the only FCM credential. Mount it read-only into the container;
never commit it (see [Cross-cutting principles](#cross-cutting-principles)).

### Push dispatch

Every stored event is pushed to every client that has a push target. There is
no filtering yet: which events interrupt the owner is a preference (roadmap
R12), and it will be decided from generic event fields only.

```
 POST /api/v1/events ──one transaction──▶ events + push_dispatches (outbox)
                                              │ every 2 s
                                              ▼
                        EventPushDispatcher: claim oldest row ──▶ PushDelivery.deliver(client, message)
                                              │                     for each client with a push target
                                              └─ delete the row
```

- **Durable.** Publishing writes the event and a `push_dispatches` row in the
  same transaction (V5), so an acknowledged event always gets its push
  attempted, even if the backend stops before sending it.
- **Claims, not locks.** The dispatcher claims the oldest row for 5 minutes
  (`FOR UPDATE SKIP LOCKED` picks it), sends outside any transaction, and then
  deletes the row. If the backend stops mid-dispatch, the claim expires and
  the event is dispatched again. Runs never overlap, and further instances
  would skip each other's claims.
- **At least once.** A redispatched event reaches again the clients that had
  already received it, so clients deduplicate by the `eventId` in the push
  data. Each client gets one send per dispatch; a transient provider failure
  is logged and not retried yet (roadmap R13).
- **The push.** The event's title, its message shortened to 500 characters
  (providers limit payloads; FCM to 4 KiB), and data `eventId`, `category`
  and `severity`. It is a signal to look: the client fetches the event by ID.
- **Interval.** `signalhub.push.dispatch.interval`
  (`SIGNALHUB_PUSH_DISPATCH_INTERVAL`, default `2s`) is how often the
  dispatcher looks for new rows, and so the longest a push waits.
- Deleting an event (not possible through the API yet) drops its pending
  push with it.

**Not yet:** retries, backoff and delivery-attempt records (roadmap R13), and
preferences for which events push (roadmap R12). The push token never appears in logs:
providers must keep it out of outcome details, and an exception from a
provider is logged by type only.

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
> connectivity, migrations, health, OpenAPI, container). The product API is
> described in [Events](#events) and [Producers and authentication](#producers-and-authentication).

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
  resource (HTTP), request and response records (API models), the parsed
  listing query and its cursor, a service (transactions and mapping), and the
  JPA entity with a Panache repository (persistence). The entity is package-private and never serialized.
  Producers, API keys, their authentication filters, and the management API
  live in the `producer` package. Clients, client keys, the client and owner
  authentication filters, and the client APIs live in the `client` package.
  The push-provider boundary and delivery live in the `push` package; concrete
  providers (`FcmPushProvider`) are classes there too, and nothing outside it
  references one. Authentication uses plain JAX-RS request
  filters bound by annotation (`@ProducerAuthenticated`, `@AdminOnly`,
  `@ClientAuthenticated`, `@OwnerAuthenticated`) rather than an identity
  framework: a few bearer-token checks do not justify one.
  Cross-cutting HTTP concerns (strict JSON reading, error bodies, identifier
  rules) live in `api`.
- **Deployment:** `compose.yaml` runs the backend and PostgreSQL 17 with a
  named volume. The backend starts after the database is healthy and is
  itself health-checked through readiness.

## Cross-cutting principles

- **Durability first:** persist, then acknowledge, then deliver.
- **Idempotency:** producers may retry, so ingestion should support
  deduplication. Not implemented yet; see [IDs](#ids).
- **Secrets from the environment:** credentials (the admin token, push-provider
  credentials, database password) come from runtime configuration, never from
  the repository. Producer API keys are generated by the server and stored
  only as hashes.
- **Versioned contracts:** the producer API and event schema are public
  contracts. Breaking them is a breaking change under the release policy in
  [development.md](development.md).

## Open questions

These are deferred until the relevant implementation work:

- Requiring a credential for `GET /api/v1/events/{id}` (a breaking change).
- How a client obtains its key without the operator copying it by hand
  (for example a pairing flow), once a client application exists.
- Event retention and pruning policy.
- Routing and filtering rules: which events trigger a push (all do for now),
  quiet hours.
- Client platforms: which clients (Android, iOS, web, CLI) are built first,
  and their technology.
