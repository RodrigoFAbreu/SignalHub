# Architecture

> Status: implemented: the backend (see [Backend platform](#backend-platform)),
> generic event ingestion, the event listing and read state (see
> [Events](#events)), producer authentication (see
> [Producers and authentication](#producers-and-authentication)), client
> registration with client keys, push targets and push preferences (see
> [Clients](#clients)), push delivery through Firebase Cloud Messaging with
> bounded retries (see [Push delivery](#push-delivery)), the Flutter client
> app for Android and iOS (see [Client application](#client-application)),
> the Python producer SDK and command (see
> [Producer SDK and CLI](#producer-sdk-and-cli)), the
> [integration examples](#integration-examples), and metrics, logs,
> retention, backup and restore (see [Operations](#operations)); what stays
> compatible is in [Compatibility](#compatibility).
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
> the admin token), which also read single events by ID. Compose publishes
> the API on localhost only; a TLS reverse proxy exposes it (see
> [deployment.md](deployment.md)).

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
| `link` | `http`/`https` URL, ≤ 2000 | no | producer | One URL the owner can open from the event (below). |
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
change, but the reverse is not. Adding a value needs a migration for the
database check constraint and is a `feat`, not a breaking change, because
clients must accept values they do not know (see
[Compatibility](#compatibility)); removing or renaming one is breaking.

### IDs

The server generates every ID as a UUIDv7 (RFC 9562): globally unique without
coordination, safe to expose, and roughly ordered by creation time, which
keeps primary-key inserts cheap. Producers cannot supply `id` (or
`createdAt`): unknown fields are rejected, so a producer that tries gets a 400
rather than a silently different ID. The same holds for the producer.

Retries are made safe by an optional producer-supplied key, scoped to the
producer (see [Idempotent publishing](#idempotent-publishing)), not by a
producer-controlled canonical ID.

### Idempotent publishing

A producer that gets no answer (a timeout, a dropped connection) cannot tell
whether its event was stored. Sending it again is safe only with an
**idempotency key**, sent in the `Idempotency-Key` header:

```http
POST /api/v1/events
Authorization: Bearer shpk1_...
Idempotency-Key: nightly-1842-1
```

- **One key, one event.** The key names one event of this producer: a CI run
  and attempt, a job ID with a date, or a UUID the producer generated and
  kept for its retries. Keys are 1 to 200 visible ASCII characters (no
  spaces), compared exactly; anything else is `400` with a violation for
  `Idempotency-Key`. Without the header, or with it empty, every request
  stores an event, as before.
- **The same event again** with a key the producer already used stores
  nothing: the answer is `200` (not `201`) with the stored event, as it is
  now (its `readAt` may have changed), and its `Location`. No second push is
  sent. "The same" compares the stored fields (`context`, `category`,
  `severity`, `title`, `message`, `metadata`, `link` and `occurredAt`) as they are
  stored, so key order and whitespace in `metadata` and the offset of
  `occurredAt` do not matter.
- **A different event** with a used key is `422`, and nothing is stored: the
  key is being reused by mistake, and either storing the new event or
  answering the old one would hide it.
- **Scoped to the producer.** Two producers may use the same key; a producer
  never learns anything about another's keys.
- **As long as the event exists.** There is no separate expiry: the key is
  kept with its event and freed when [retention](#retention) deletes it, so a
  producer that retries for longer than the retention period may store the
  event again.
- **Concurrent requests** with the same key wait for each other (publishing
  is serialized, see [Listing events](#listing-events)): one stores the event, the
  others answer it.

Authentication and validation come first: a request with an invalid key or
body gets the same `401` or `400` as without the header.

### Timestamps

- All timestamps are ISO-8601 strings with an explicit UTC offset, stored as
  PostgreSQL `timestamptz` and returned in UTC (`Z`) with up to microsecond
  precision. Finer precision is truncated.
- `createdAt` is canonical: the server's clock when it stored the event,
  always later than every event stored before it (see
  [Listing events](#listing-events)). Ordering and [retention](#retention)
  use it.
- `occurredAt` is producer context. SignalHub stores and returns it but does
  not trust it for ordering: producer clocks may be wrong, and events may be
  published late. A timestamp without an offset (`2026-09-25T14:03:00`) is
  rejected because it is ambiguous, as are epoch numbers. The year must have
  four digits (0001–9999). The offset the producer sent is not kept; only the
  instant is.

### Metadata

`metadata` is an optional JSON object for producer-specific data, for example a
CI run number, a workflow step, or further links (the one the owner should
open goes in [`link`](#link)). SignalHub stores it as PostgreSQL
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

### Link

`link` is an optional URL the owner can open from the event, such as the
page of a failed CI run or of a pull request waiting for review. It is
generic: one link, with no label and no meaning SignalHub knows of; any
further URLs a producer has belong in metadata.

- It must be an absolute `http` or `https` URL with a host
  (`https://ci.example.com/runs/1842`), at most 2000 characters. Anything
  else, a relative URL, another scheme (`javascript:`, `file:`, `intent:`,
  `mailto:`) or characters a URL may not contain unescaped such as spaces,
  is `400` with a violation for `link`, so a client can hand every stored
  link to a browser. Hosts are ASCII: an internationalized name is sent in
  its `xn--` form.
- It is stored and returned exactly as sent (no normalization), and `null`
  when the producer sent none, as for every event stored before v2.3.0.
- SignalHub never fetches, follows or checks it: whether it is reachable,
  and what it points to, is the producer's business. The push message does
  not carry it; the app reads the event by its ID, as for every other field.

### HTTP API

| Method and path | Result |
|---|---|
| `POST /api/v1/events` | Requires a producer API key. Validates and stores an event bound to that producer. `201 Created` with the canonical event and a `Location` header. With an optional `Idempotency-Key` header the producer already sent, `200` with the event stored then. See [Idempotent publishing](#idempotent-publishing). |
| `GET /api/v1/events` | Requires a client key or the admin token. One page of events, newest first, optionally filtered. See [Listing events](#listing-events). |
| `GET /api/v1/events/{id}` | Requires a client key or the admin token. `200` with the event, or `404`. |
| `PUT /api/v1/events/{id}/read` | Requires a client key or the admin token. Marks the event read; `200` with the event, or `404`. See [Read state](#read-state). |
| `DELETE /api/v1/events/{id}/read` | Requires a client key or the admin token. Marks the event unread; `200` with the event, or `404`. |
| `POST /api/v1/events/read` | Requires a client key or the admin token. Marks read every unread event up to a given one; `200` with the count. |
| `GET /api/v1/events/unread-count` | Requires a client key or the admin token. `200` with the number of unread events. |

The event is committed to PostgreSQL before `201` is returned. Errors:

- `401` when publishing without a valid producer API key, or reading without
  a client key or the admin token. Authentication runs before the body is
  read and before the event is looked up, so an unauthenticated request gets
  `401` whatever its body contains, and never learns whether an event ID
  exists. See [Authentication errors](#authentication-errors).

- `400` with a JSON body `{"title", "status", "violations": [{"field", "message"}]}`
  for malformed JSON, unknown fields, wrong JSON types (values are never
  coerced, e.g. `42` is not a string), and failed validation. `field` is the
  JSON path, or empty for the whole body.
- `404` with the same body shape (no violations) for an unknown event ID. A
  malformed ID is also `404`.
- `422` with the same body shape when the producer already used the
  `Idempotency-Key` it sent for a different event (see
  [Idempotent publishing](#idempotent-publishing)).
- `413` for request bodies over 64 KiB, and `415` for non-JSON bodies.

Every error from the product API (paths under `/api/`) has this JSON body,
with an empty `violations` list when no field is at fault. That includes the
errors Quarkus raises before a resource runs: an unknown path or malformed ID
(`404`), an unsupported method (`405`), an
unacceptable `Accept` header (`406`) and a non-JSON body (`415`); their
`title` is the HTTP reason phrase, such as `"Method Not Allowed"`. The one
exception is `413`: the HTTP server refuses an oversized body before the
request is routed, so it has no body and closes the connection. Clients
should decide by the status and treat the body as a description. Releases
before v0.24.0 answered those errors without a body.

Reading an event by its ID needs the same credential as the
[listing](#listing-events): a client key or the admin token. A producer key
is refused with `401`, even for an event it published: producers publish,
and the `201` response already holds the stored event. Releases before
v0.23.0 let anyone who knew an event's ID read it.

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
(descending) among events with the same `createdAt` (which publishing no
longer produces, but events stored by releases up to v0.25.3 may have), so
the order is total and stable. `occurredAt` is not used for ordering (see
[Timestamps](#timestamps)).

**Filters.** All optional, and combined with AND. Repeating a parameter
matches any of its values (OR), e.g. `severity=HIGH&severity=CRITICAL`.

| Parameter | Meaning |
|---|---|
| `producerId` | Events of this producer (canonical ID). Repeatable. |
| `category` | Events with this category. Repeatable. |
| `severity` | Events with this severity. Repeatable. |
| `read` | `false`: only unread events (`readAt` is `null`); `true`: only read events. Anything else is `400`. See [Read state](#read-state). |
| `createdFrom` | Events with `createdAt` at or after this time (inclusive). |
| `createdBefore` | Events with `createdAt` before this time (exclusive). |

Timestamps follow the same rules as in request bodies: ISO-8601 with an
explicit offset. In a URL, write a `+` offset as `%2B`, or use `Z`. Filters
use only generic fields; there is no filtering on `context`, metadata, or
text, and no full-text search. `read=false` is served by the partial index
over unread events in listing order (V6), so the unread-only view costs the
same per page however many events are read.

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
- With `read`, whether an event matches is decided when each page is read.
  Paging through `read=false` while events are marked read or unread never
  repeats an event of an earlier page; a later page lists the events after
  the cursor that are unread by then.
- Cursors are versioned internally; a client must not construct or parse
  them, only pass them back.
- Events become visible in listing order: publishing is serialized (a
  PostgreSQL advisory lock held until the event commits), and `createdAt` is
  taken under that lock, later than every stored event's (one microsecond
  after the newest if the clock has not moved on or was set back). So a
  reader that sees an event also sees every event listed after it, and a
  client may stop paging at the newest event it already had without missing
  one; `POST /api/v1/events/read` never marks an event its client has not
  had a chance to list. Releases up to v0.25.3 took `createdAt` before
  storing the event, so one could become visible a moment after a newer one.
  Serializing costs throughput only with many producers publishing at once,
  far beyond one owner's events.

Invalid parameters get `400` with one violation per problem, naming the
parameter in `field` (e.g. `limit`, `category`, `cursor`). An unknown
producer ID is not an error; it just matches no events. Unknown query
parameters are ignored.

### Read state

Every event is either unread or read, and read state belongs to the owner,
not to a client: an event one client marks read is read on every client.
SignalHub has a single owner, so this is one nullable `readAt` per event,
not a per-client or per-user table.

- A stored event starts unread: `readAt` is `null` in every representation
  of it, including the `201` answer to its producer.
- `PUT /api/v1/events/{id}/read` marks it read and answers the event. It is
  idempotent: marking a read event again keeps its first `readAt`.
- `DELETE /api/v1/events/{id}/read` marks it unread again, also idempotent.
- `POST /api/v1/events/read` with `{"through": "<event id>"}` marks read
  every unread event at or before that event in listing order (the event
  and everything older) and answers `{"marked": <count>}`. A client passes
  the newest event it shows, so events that arrived since stay unread;
  there is deliberately no "mark everything" without a position.
- `GET /api/v1/events/unread-count` answers `{"unread": <count>}`.

All four require one of the owner's credentials, like the listing; producers
never change or see read state except as `readAt` in event representations.
An unknown event ID (also as `through`) is `404`. Marking read changes
nothing about delivery: pushes are sent whether or not an event is read.
Concurrent marks from several clients are safe: each is one conditional
`UPDATE`, and marking read never moves an existing `readAt`.

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
`V6__add_event_read_state.sql` adds the nullable `read_at` column (existing
events start unread) and a partial `(created_at, id)` index over unread
events, which serves the unread count and marking read up to an event.
`V9__add_event_idempotency_key.sql` adds the nullable `idempotency_key` column
(existing events have none), checked against the key format, and a partial
unique index on `(producer_id, idempotency_key)` over events that have one.
`V11__add_event_link.sql` adds the nullable `link` column (existing events
have none), checked to be 1 to 2000 characters; the API checks the scheme.

## Producers and authentication

> Status: implemented. Producers authenticate with API keys; the owner's
> clients have their own keys (see [Clients](#clients)), and the operator an
> admin token. There are no user accounts: SignalHub has one owner.

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
`POST /api/v1/events` takes a producer key.

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
| `GET /api/v1/admin/producers` | All producers with their key records, by name, as `{"items": [...]}`. |
| `GET /api/v1/admin/producers/{id}` | One producer with its key records. |
| `POST /api/v1/admin/producers/{id}/keys` | Issues an additional key. `201` with `keyId` and `apiKey`. |
| `POST /api/v1/admin/producers/{id}/keys/{keyId}/revoke` | Revokes a key, immediately and permanently. Idempotent. |
| `POST /api/v1/admin/producers/{id}/disable` | Disables the producer: none of its keys authenticate. Idempotent. Events are kept. |
| `POST /api/v1/admin/producers/{id}/enable` | Re-enables it: its unrevoked keys work again. |

Unknown producer or key IDs get `404`, as does a key ID used with another
producer's path.

Both management listings (producers and [clients](#client-api)) answer an
object, `{"items": [...]}`, like the [event listing](#listing-events), so
fields such as paging can be added later without breaking them. Releases
before v0.26.0 answered a bare JSON array: a script that read them with, for
example, `jq '.[]'` now reads `.items[]`.

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

Every product API endpoint requires a credential. This version does not yet:

- **Terminate TLS itself.** Keys and the admin token travel as bearer
  credentials, so any non-local access goes through a TLS reverse proxy: the
  `proxy` profile of `compose.yaml` (Caddy), which forwards only `/api/`
  without the management API (see [deployment.md](deployment.md)). Compose
  publishes the backend itself on `127.0.0.1` only.
- **Rate-limit** authentication attempts. Guessing is infeasible (256-bit
  secrets, 128-bit pairing codes that expire in 10 minutes), but a flood of
  requests still costs a database lookup each.
- **Separate the management API** onto its own port or network. It is
  protected by the admin token, disabled by default and not forwarded by the
  Compose proxy, so it is reachable only on the host; for the tightest
  setup, set `SIGNALHUB_ADMIN_TOKEN` only while managing producers or
  clients, and restart without it afterwards; clients keep reading with
  their own keys.
- **Expire keys** automatically. Keys are valid until revoked.
- **Scope keys**: every valid key may publish any event as its producer.
- **Delete** revoked producer keys. They are kept, and listed by the
  management API, as a record of what was issued. Revoked clients can be
  [deleted](#deleting-a-revoked-client), so devices paired again do not
  pile up in the list; once deleted, the `INFO` log lines of registering,
  revoking and deleting are the only record that the client existed.

**A stolen admin device** (its client key copied, or the device lost
unlocked) can do what an [admin device](#device-management-from-an-admin-device)
can, through the proxy, until the operator acts: read every event, list every
device (names, push providers and push results, never keys or push tokens),
make other devices admins, revoke devices that are not admins, delete
revoked devices, and create pairing codes for new devices that are not
admins. It cannot revoke an admin or take admin rights away, rename a
device, pair an admin device, publish, or reach the management API, so the
owner's admin devices keep working and the operator keeps control. Deleting
takes nothing from a working device, since only revoked ones can be
deleted, but it removes them from the list, so the device list alone no
longer shows everything that happened: the log does. Every change it makes,
and every device paired with its codes, is logged and pushes a notice to
the owner's devices naming it; a deletion is logged but pushes nothing. To recover, on the [admin page](#the-admin-page) (or the management API)
with the admin token: revoke the stolen device (its unused pairing codes
stop working with it), revoke any device paired with its codes, take admin
rights away from, or revoke, any device it made an admin, and pair again any
device it revoked (a revoked client cannot be restored, and a deleted one
is gone: its ID remains in the log lines `Client <caller> revoked client
<id>` and `Client <caller> deleted client <id>`). Keep few admin devices:
each is a key that can do this.

## Clients

> Status: implemented. Clients are registered by the operator or by
> [pairing](#pairing) a device, authenticate with client keys,
> read events, and store a push target that receives pushes (see
> [Push delivery](#push-delivery)), filtered by the client's
> [push preferences](#push-preferences).

A **client** is one installation of a SignalHub client application on one of
the owner's devices: a phone app, a desktop app, a CLI. SignalHub has one
owner, so a client is not a user account: it is a credential for reading the
owner's events plus, optionally, where to push notifications. The model is
the same for every platform.

| Field | Meaning |
|---|---|
| `id` | Server-generated canonical ID (UUIDv7). |
| `name` | Human-readable label chosen by the owner, e.g. `Pixel 8`. 1–100 characters, not blank. Need not be unique. The operator can rename a client. |
| `admin` | Whether the client is one of the owner's [admin devices](#admin-devices). `false` unless the operator, or another admin device, makes it one. |
| `createdAt` | When it was registered. |
| `revokedAt` | Set once the client is revoked; `null` while it is active. |
| `pushTarget` | `{provider, updatedAt}`, or `null` if the client has no push target. |
| `pushPreferences` | Which events are pushed to it: `{enabled, minimumSeverity, mutedCategories, mutedProducerIds}`. See [Push preferences](#push-preferences). |

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
A revoked client can then be [deleted](#deleting-a-revoked-client).

**What a client key may do:** read the event listing, and read and change its
own registration (push target and push preferences) under `/api/v1/client`.
It cannot rename itself or take its own admin rights away. It cannot publish,
manage producers, or see push tokens of other clients. Only an
[admin device](#admin-devices)'s key may list the other clients, make one an
admin, revoke one that is not an admin, delete a revoked one (see
[Device management from an admin device](#device-management-from-an-admin-device))
and create pairing codes (see
[Pairing from an admin device](#pairing-from-an-admin-device)).

### Admin devices

The operator can make any client an **admin device**, to mark the devices of
the owner (or of whoever the owner trusts to manage SignalHub) apart from
devices lent or given to others. Each client response has `admin`, including
a client's own registration (`GET /api/v1/client`), so an app can tell that
it is one.

- **The operator sets it,** with the admin token: when registering a
  client or creating a pairing (`"admin": true`, optional, `false` when
  omitted), or afterwards with `PATCH /api/v1/admin/clients/{id}`
  (`{"admin": true}` or `{"admin": false}`), usually from the
  [admin page](#the-admin-page). An admin device can also make another
  device an admin, but only the operator can take admin rights away; no
  other client key can change it.
- **It lets the device manage the others,** within limits, and pair new
  devices that are not admins: see
  [Device management from an admin device](#device-management-from-an-admin-device)
  and [Pairing from an admin device](#pairing-from-an-admin-device).
  Otherwise an admin device reads events and keeps its own registration
  exactly like any other client.
- **Existing clients are not admins.** `V13__add_client_admin.sql` adds the
  column with `false` for every client and unredeemed pairing, so upgrading
  needs no operator action.
- **Revoking works the same** for an admin device as for any other client,
  with the admin token; an admin device cannot revoke an admin.

### Device management from an admin device

An admin device manages the owner's other devices with its own client key,
under `/api/v1/client/devices`, so the [proxy](deployment.md#network-exposure)
forwards it like the rest of the client API and the device needs neither the
admin token nor the host:

| Method and path | Result |
|---|---|
| `GET /api/v1/client/devices` | Every client, revoked or not, oldest first, as `{"items": [...]}`: exactly what `GET /api/v1/admin/clients` returns (schema `ManagedClient`, with `pushStatus`), never a key or a push token. |
| `POST /api/v1/client/devices/{id}/admin` | Makes the client an admin device. `200` with the client; `200` and no change if it already is one (the caller included); `409 Client is revoked` for a revoked client; `404` for an unknown ID. |
| `POST /api/v1/client/devices/{id}/revoke` | Revokes a client that is not an admin and removes its push target, as the operator's revoke does. `200` with the client; `200` and no change if it is already revoked; `409 Client is an admin device` for an admin, the caller included; `404` for an unknown ID. |
| `DELETE /api/v1/client/devices/{id}` | [Deletes a revoked client](#deleting-a-revoked-client), an admin or not, as the operator's delete does. `204`; `409 Client is not revoked` for an active client, the caller included; `404` for an unknown ID or one deleted already. |

An admin device also creates pairing codes, with `POST
/api/v1/client/pairings` under the same rules: see
[Pairing from an admin device](#pairing-from-an-admin-device).

No request has a body. The limits keep a stolen admin device from taking
over:

- **Only an admin device's key is accepted.** Every other client key gets
  `403 Not an admin device` on every path, before the path's client is looked
  up, so the answer is the same whatever the target and says nothing about
  it. A missing, unknown or revoked key is the usual `401`, and the admin
  token is not a client key (`401`): the operator has the
  [management API](#client-api). The caller's admin flag is read, and its
  row locked, in the transaction that makes the change, so a device whose
  rights the operator took away, or that the operator revoked, cannot make
  a change after that.
- **An admin device can do nothing to an admin**, itself included: it cannot
  take admin rights away (there is no endpoint for it) or revoke an admin.
  Only the operator can, with the admin token, usually on the
  [admin page](#the-admin-page). Renaming is the operator's too. A revoked
  admin can be deleted: it can no longer act.
- **Every change is logged** at `INFO` with client IDs only: `Client <caller>
  made client <id> an admin device`, `Client <caller> revoked client <id>`
  and `Client <caller> deleted client <id>`. A request that changes nothing
  or is refused logs nothing.
- **The owner's devices are told** of every change but a deletion, which
  changes nothing a device can use. A change pushes a
  [notice](#pairing-notice), naming the device that made it, to every client
  that has a push target and has not paused pushes, the calling device
  included (its key may be in someone else's hands):

  ```
  Device made an admin
  "Anna's phone" made "Tablet" an admin device. If this was not you, revoke both on the admin page.
  ```

  ```
  Device revoked
  "Anna's phone" revoked "Old tablet". If this was not you, revoke "Anna's phone" on the admin page.
  ```

  with the data `{"notice": "client-made-admin"}` or `{"notice":
  "client-revoked"}` and `clientId` (the changed client) and `byClientId`
  (the calling device). It is sent like the pairing notice: after the
  change commits, once, without retries, never failing the request. A
  request that changes nothing sends nothing; a revoked device has no push
  target, so it is not told.

What a stolen admin key can do, and how to recover, is in
[Security limitations](#security-limitations).

### Renaming a client

`PATCH /api/v1/admin/clients/{id}` also renames a client (`{"name": "Anna's
phone"}`), with the same rules as registering (1–100 characters, not blank,
no NUL); the key keeps working. A body may rename and change `admin`
together; a field that is omitted or `null` stays as it is, and a body that
changes nothing is `400`. It answers `200` with the client as `GET` returns
it (schema `ManagedClient`), `404` for an unknown ID, and **`409 Conflict`
for a revoked client**, which never changes: it is no longer one of the
owner's devices, and its name and flag stay the record of what it was.
Setting a field to the value it has is `200` and changes nothing.

Every change is logged at `INFO` with the client ID only, like registering and
revoking: `Renamed client <id>`, `Client <id> is now an admin device`,
`Client <id> is no longer an admin`, and `Registered client <id> as an admin
device`.

### Deleting a revoked client

A revoked client stays in the list, so a phone paired again would show up
twice. `DELETE /api/v1/admin/clients/{id}` (admin token), or `DELETE
/api/v1/client/devices/{id}` from an
[admin device](#device-management-from-an-admin-device), removes it for
good. Usually it is done on the [admin page](#the-admin-page), or from an
admin device's device list in the app ([Client application](#client-application)).

- **Only a revoked client.** An active client, an admin device included,
  answers `409 Client is not revoked` and does not change: revoke it first.
  A revoked admin can be deleted too, since it can no longer act.
- **`204` with no body**; `404` for an unknown ID, so deleting twice
  answers `404` the second time. There is no undo.
- **What goes with it:** everything that exists only for the client, its
  push results (columns of its row), its pushes waiting for a retry
  (`push_retries`) and the unused pairing codes it created as an admin
  device (`pairings.created_by`). Both tables reference `clients` with `ON
  DELETE CASCADE` since they were created, so no migration was needed and
  upgrading needs no operator action; a test checks that every foreign key
  to `clients` cascades. A push to it already under way when it is deleted
  records nothing and is not retried.
- **What stays: every event,** with its read state. Read state is the
  owner's, not a client's (see [Read state](#read-state)), and events are
  never deleted with a client.
- **Logged** at `INFO` with client IDs only, as revoking is: `Deleted client
  <id>`, or `Client <caller> deleted client <id>` from an admin device. No
  push is sent. Once deleted, those log lines are the only record of the
  client (see [Security limitations](#security-limitations)).

### Pairing

Pairing lets a new device register itself, so setting it up needs neither
the admin token on the device nor typing a client key:

1. The operator creates a **pairing** for a client name with the admin token
   (`POST /api/v1/admin/pairings`, `{"name": "Pixel 8"}`, and `"admin": true`
   to pair an [admin device](#admin-devices)), or an admin device does
   ([Pairing from an admin device](#pairing-from-an-admin-device)). The
   response has the pairing's `id`, a one-time **pairing code**, when it
   expires, and a **pairing URI** to show as a QR code (for example with
   `qrencode`, see [development.md](development.md#pairing-a-device)).
2. The device redeems the code once, before it expires:
   `POST /api/v1/pairing` with `Authorization: Bearer <code>` and no body.
   SignalHub registers a new client of that name (an admin device if the
   pairing said so), exactly as the management
   API does, and returns it with its client key (`201`, the same body as
   registering a client), shown only in that response.
3. Whoever shows the code, the operator or the admin device that created
   it, can ask whether it was used, and by which device
   ([Whether a code was used](#whether-a-code-was-used)).

```
shpc1_Zt1vQ3x9rB2mKc8wYp4aLd        pairing code
signalhub://pair?server=https%3A%2F%2Fsignalhub.example.com&code=shpc1_Zt1vQ3x9rB2mKc8wYp4aLd
```

- **Codes.** A format prefix (`shpc1_`, "SignalHub pairing code", version 1,
  distinct from client and producer keys) and a 128-bit random secret,
  base64url (22 characters). That makes guessing infeasible for a code that
  lives minutes, and keeps the QR code small. Only `SHA-256(code)` is stored
  (`pairings.code_hash`).
- **Ten minutes, once.** A code expires 10 minutes after it is created.
  Redeeming it marks the pairing redeemed, with the time and the new
  client's ID (`pairings.redeemed_at`, `pairings.redeemed_by`), in the same
  transaction that registers the client, and a redeemed pairing never
  redeems again. The pairing's row is locked while it is redeemed, so two
  concurrent redemptions of one code make one client. Pairings, used or
  not, are deleted when a pairing is created more than 10 minutes after
  they expired; until then their status can be read. A missing, malformed,
  unknown, used or expired code gets the same `401` as a wrong key (see
  [Authentication errors](#authentication-errors)).
- **Its own client.** A paired device is an ordinary client with its own key,
  listed and revoked through the management API like any other; no key is
  shared between devices. Registering a client with the management API and
  giving the device its key by hand keeps working.
- **The URI.** `signalhub://pair?server=<address>&code=<code>`, the address
  percent-encoded. The address is `SIGNALHUB_PUBLIC_URL`, where devices reach
  the server; SignalHub cannot learn it from the request, because the
  operator creates pairings on the host, not through the proxy. Compose
  defaults it to `https://` and `SIGNALHUB_DOMAIN` when the proxy is set up.
  Without it, `uri` is `null` and the device is given the address and the
  code separately. It must be an absolute `http` or `https` URL without
  credentials, query or fragment, or startup stops; a trailing slash is
  dropped.
- **Reachable.** `/api/v1/pairing` is outside `/api/v1/admin/`, so the Compose
  proxy forwards it; creating pairings with the admin token is management and
  stays on the host, and an admin device creates them through the proxy
  ([Pairing from an admin device](#pairing-from-an-admin-device)).
- **Nothing provider-specific.** A pairing holds only a client name and
  whether it is an admin device; push is
  set up afterwards with the client key, as for any client.
- **The owner is told.** Once a code is redeemed, the owner's devices get a
  push (see [Pairing notice](#pairing-notice)), so a code that leaked is
  noticed when it is used.

#### Whether a code was used

Whoever shows a pairing code learns, by asking, when a device has used it,
so the admin page (and the app, from an admin device) can say which device
connected and get ready for the next one:

| Method and path | Credential | Result |
|---|---|---|
| `GET /api/v1/admin/pairings/{id}` | admin token | A pairing the operator created: `200` with its `PairingStatus`. |
| `GET /api/v1/client/pairings/{id}` | admin device's client key | A pairing this device created: `200` with its `PairingStatus`. |

```json
{"id": "01997d5e-...", "state": "REDEEMED", "expiresAt": "2026-09-27T10:10:00.123456Z",
 "redeemedAt": "2026-09-27T10:02:41.654321Z",
 "client": {"id": "01997d60-...", "name": "Pixel 8"}}
```

- **States.** `PENDING`: the code still works. `REDEEMED`: a device redeemed
  it, and `client` is that device's ID and its name now (it may have been
  renamed since). `EXPIRED`: it expired unused. `redeemedAt` and `client` are
  `null` unless `REDEEMED`. An asker that meets a state it does not know
  treats it as `PENDING`, so a state added later is compatible.
- **Polling, not pushing.** The asker polls while it shows the code; the
  admin page asks every 2.5 seconds. For one owner that costs a lookup by
  primary key now and then, and needs no connection held open.
- **Kept long enough.** Redeeming no longer deletes a pairing: it is kept,
  used or not, until a pairing is created more than 10 minutes after it
  expired, so a used code is told from an expired one even by an asker whose
  clock is late. Deleting the client it made deletes it too. After that it
  is `404`, like an unknown ID.
- **Only the creator's own.** The admin token answers only about pairings
  created with it, and an admin device only about those it created; any
  other pairing, another device's or the operator's, is `404` exactly like an
  unknown ID. The client API part is admin only, as
  [device management](#device-management-from-an-admin-device): every other
  client key gets `403 Not an admin device` before the pairing is looked up,
  and a missing, unknown or revoked key `401`, the admin token included. A
  code whose admin device is revoked or no longer an admin stops working and
  is deleted; that device can no longer ask either.
- **No secrets.** The status never holds the code or a key, only IDs, times
  and the new device's name. The pairing ID is not a secret: it redeems
  nothing.
- **No operator action.** `V15__add_pairing_redemption.sql` adds the two
  nullable columns; pairings that existed before are unredeemed, as
  redeeming used to delete them.

#### Pairing from an admin device

An [admin device](#admin-devices) creates pairing codes with its own client
key, so the owner can add a device from the app, away from the host:

| Method and path | Result |
|---|---|
| `POST /api/v1/client/pairings` | Creates a pairing for a new client (`{"name": "Pixel 8"}`), exactly like the operator's: `201` with `{"id", "name", "admin", "code", "expiresAt", "uri"}`, `admin` always `false`. The code redeems at `POST /api/v1/pairing` like any other. |
| `GET /api/v1/client/pairings/{id}` | Whether a pairing this device created was used, and by which device; `404` for any other pairing. See [Whether a code was used](#whether-a-code-was-used). |

- **Admin only, as device management.** Every other client key gets `403 Not
  an admin device`; a missing, unknown or revoked key is `401`, and so is the
  admin token, which has `POST /api/v1/admin/pairings`. The caller's row is
  locked while the pairing is created, as for
  [device management](#device-management-from-an-admin-device). The body is
  validated first (`400` for a blank or long name, as when registering).
- **Never an admin device.** The body has only `name`; `admin`, `true` or
  `false`, is an unknown property and `400`. A pairing code is a bearer
  secret handed over by link or QR code, so it is the part most likely to
  leak; a code from a device therefore only ever gives a device that reads
  events. Making the new device an admin is a separate step, from an admin
  device or the admin page, that pushes its own notice. This also keeps a
  stolen admin device from quietly minting further admin devices: it can
  still make an existing device an admin, but every such change names it.
- **Only while its device stays an admin.** The pairing records the device
  that created it (`pairings.created_by`, added by
  `V14__add_pairing_created_by.sql`; empty for pairings created with the
  admin token, so upgrading needs no operator action). If that device is
  revoked or is no longer an admin when the code is redeemed, the code gets
  the usual `401` and is deleted: revoking a stolen admin device also stops
  the codes it handed out. Its row is locked while the code is redeemed, so
  the operator's change applies before the redemption or after it.
- **Logged** at `INFO` with IDs only: `Client <caller> created pairing <id>,
  expires at <time>`, then `Redeemed pairing <id> as client <new client>` as
  for every pairing. A refused request logs nothing.
- **The owner's devices are told** who created the code when it is redeemed,
  the creating device included (see [Pairing notice](#pairing-notice)).
- **The URI** is built from `SIGNALHUB_PUBLIC_URL`, as for the operator's
  pairings. Without it, `uri` is `null`, and the app builds the same URI from
  the address it reaches the server at, which is where the new device should
  go too.

### The admin page

`/admin/` is the operator's page for the owner's devices, the management API
for clients and pairings without a terminal. After the operator types the
admin token, it shows every client, revoked or not: its name, whether it is
an admin, when it was created or revoked, whether it has a push target, and
its last push results (`pushStatus`). For each device that is not revoked,
it can:

- **Rename** it, so the owner can tell whose or what each device is;
- **Make it an admin** or **take admin rights away** (see
  [Admin devices](#admin-devices));
- **Revoke** it, admin devices included, after a confirmation.

A revoked device offers only **Delete**, after a confirmation, which
removes it from the list for good (see
[Deleting a revoked client](#deleting-a-revoked-client)). Active devices
have no delete: they must be revoked first.

**Connect a device** creates a pairing for a device name, optionally as an
admin device, and shows the pairing URI as a QR code, counts down to its
expiry and blurs the code once it has expired. It copies the QR code as an
image or the URI as text, or downloads the image, so the code can be sent to
someone whose device should connect. While the code is shown, the page asks
every 2.5 seconds whether it was used
([Whether a code was used](#whether-a-code-was-used)), and once more when it
expires. Once a device has used it, a toast says that the device (by name)
connected with the pairing code, the QR code and the link disappear, the
form goes back to its first state (the device name and _Create pairing
code_) and the device list is read again, showing the new device. An
expired code stays blurred until a new one is created, and the page stops
asking. The device list is also read again after every change and with
**Refresh**.

- **On the host only.** The page is on the backend's own port, like `/q/`
  and the management API; the Compose proxy forwards only `/api/`, so it
  never reaches other machines. From another computer, reach it through SSH
  (`ssh -L 8080:localhost:8080 <host>`, then `http://localhost:8080/admin/`).
- **Static, and nothing without the token.** The page and its script are
  static files; everything it does is a management API call, with the token
  typed into the page. Without the admin token, or with the management API
  off, it shows the error and nothing else. The token stays in the page's
  memory: it is not stored, and is gone when the tab closes. Device names
  are shown as text, never as HTML.
- **Locked down.** The page runs only its own scripts (a
  `Content-Security-Policy` of `default-src 'none'`, with `'self'` for
  scripts, styles and requests), cannot be framed, is never cached and sends
  no referrer.
- **One dependency.** The QR code is drawn in the browser by
  [qrcode-generator](https://github.com/kazuhikoarase/qrcode-generator)
  (MIT), a Maven dependency of the backend (a WebJar) served from its jar,
  version-pinned in `pom.xml` like any other. No CDN, no network access.
- **Sharing a code** gives one device, whoever holds it, its own client
  until the code is used or expires. The page says so next to the buttons.
  The device is revoked like any other client, and the owner's devices are
  told when it connects.
- **It needs `SIGNALHUB_PUBLIC_URL`** for pairing, as the URI does; without
  it, the page says to set it.
- **`/connect/`**, the Connect page of earlier releases, is gone: its
  pairing codes are part of this page, and `/connect` and `/connect/`
  answer `404`, on the backend's own port as through the proxy. Bookmarks
  to it must be changed to `/admin/`.

### Pairing notice

When a device redeems a pairing code, SignalHub pushes a notice to every
other client that has a push target and has not paused pushes:

```
New device paired
"Pixel 8" can now read your SignalHub events. If you did not pair it, revoke it.
```

or, when the pairing made an [admin device](#admin-devices):

```
New admin device paired
"Pixel 8" is an admin device and can now read your SignalHub events. If you did not pair it, revoke it.
```

with the data `{"notice": "client-paired", "clientId": "<the new client>"}`.
When the code was created [from an admin device](#pairing-from-an-admin-device),
the notice names that device too, and goes to it as well, since its key may
be in someone else's hands:

```
New device paired
"Pixel 8" can now read your SignalHub events. "Anna's phone" created its pairing code. If this was not you, revoke both on the admin page.
```

with `byClientId` (the device that created the code) added to the data.
An app shows it like any push; it has no `eventId`, so tapping it opens the
app. The client's other [push preferences](#push-preferences) (minimum
severity, muted categories and producers) are about events and do not apply.

It is a notice, not an event, and deliberately lighter than
[push dispatch](#push-dispatch): nothing is stored, nothing appears in the
inbox, and it is sent once, through the same
[push delivery](#push-delivery) boundary, without retries, and counted in `signalhub.push.deliveries` like any push. It is sent after
the pairing's transaction commits, on a thread of its own, so the device
that is pairing never waits for it and a failed notice never fails a
pairing. The durable record is the log line `Redeemed pairing ... as client
...` and the client itself, listed by the management API. Registering a
client with the management API sends no notice: the operator holds its key. A device made an admin or revoked
[from an admin device](#device-management-from-an-admin-device) sends a
notice of the same kind.

### Push targets

A **push target** is where pushes for a client go: the name of a push
provider and the token that provider issued to the installation.

- `provider` is a lowercase identifier (letters, digits and `. _ -`, starting
  with a letter or digit, at most 50 characters), such as `fcm`. Any such
  name is accepted, so a client never depends on how the server is
  configured; delivery skips a target whose provider the server does not
  have (`UNSUPPORTED_PROVIDER`, see [Push delivery](#push-delivery)).
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

### Push preferences

Push preferences decide which events **interrupt** the owner on a client.
They never decide what is stored: every event is persisted and listed, and
read state works the same, whatever any client's preferences say. A
suppressed push is simply not sent to that client.

| Field | Default | An event is not pushed to the client when |
|---|---|---|
| `enabled` | `true` | it is `false` (pushes are paused; the push target is kept) |
| `minimumSeverity` | `LOW` | its severity is below this one (`LOW` < `NORMAL` < `HIGH` < `CRITICAL`) |
| `mutedCategories` | `[]` | its category is one of these |
| `mutedProducerIds` | `[]` | its producer (canonical ID) is one of these, at most 100 |

- **Per client.** Preferences belong to a client, like its push target, so
  each device can be as quiet as the owner wants: everything on the phone,
  only `CRITICAL` on a tablet. Read state, by contrast, belongs to the owner
  (see [Read state](#read-state)).
- **Generic only.** The fields are the event's generic `category`,
  `severity` and producer; nothing looks at `context`, text or metadata, and
  no producer is special. Muting a producer is by its ID, the same value the
  listing filters on.
- **Replace, not patch.** `PUT /api/v1/client/push-preferences` replaces all
  of them; an absent or `null` field takes its default, so `{}` restores
  pushing every event. Lists are returned sorted without duplicates. An
  unknown producer ID is accepted and matches no events, as in the listing.
  Unknown fields, unknown enum values and wrong JSON types are `400`.
- **Applied at dispatch.** The dispatcher reads preferences when it sends an
  event's push (normally within seconds of publishing), so a change applies
  to every event not yet dispatched. Changing or removing the push target
  keeps the preferences; a new client starts with the defaults.
- **Not yet.** Quiet hours and other time-based rules: nothing requires
  them yet, and they would need the owner's time zone.

### Client API

| Method and path | Credential | Result |
|---|---|---|
| `POST /api/v1/admin/clients` | admin token | Registers a client (`{"name": ..., "admin": ...}`, `admin` optional). `201` with the client and `clientKey`. |
| `GET /api/v1/admin/clients` | admin token | All clients, oldest first, as `{"items": [...]}`, each with its `pushStatus`. |
| `GET /api/v1/admin/clients/{id}` | admin token | One client, with its `pushStatus`. |
| `PATCH /api/v1/admin/clients/{id}` | admin token | Renames the client or makes it an admin device or not (`{"name", "admin"}`, each optional, at least one). `200` with the client and its `pushStatus`; `409` if it is revoked. See [Renaming a client](#renaming-a-client). |
| `POST /api/v1/admin/clients/{id}/revoke` | admin token | Revokes the client and removes its push target. Idempotent. |
| `DELETE /api/v1/admin/clients/{id}` | admin token | Deletes a revoked client with its push results, retries and unused pairing codes; events stay. `204`; `409` if it is not revoked; `404` for an unknown ID. See [Deleting a revoked client](#deleting-a-revoked-client). |
| `POST /api/v1/admin/pairings` | admin token | Creates a pairing for a new client (`{"name": ..., "admin": ...}`, `admin` optional). `201` with `{"id", "name", "admin", "code", "expiresAt", "uri"}`; see [Pairing](#pairing). |
| `GET /api/v1/admin/pairings/{id}` | admin token | Whether a pairing created with the admin token was used, and by which client (`PairingStatus`); `404` for an unknown ID or an admin device's pairing. See [Whether a code was used](#whether-a-code-was-used). |
| `POST /api/v1/pairing` | pairing code | Redeems the code: registers the client. `201` with the client and `clientKey`, `Location` `/api/v1/client`. |
| `POST /api/v1/client/pairings` | admin device's client key | Creates a pairing for a new client that is not an admin (`{"name": ...}`). `201` as `POST /api/v1/admin/pairings`; `403` for any other client. See [Pairing from an admin device](#pairing-from-an-admin-device). |
| `GET /api/v1/client/pairings/{id}` | admin device's client key | Whether a pairing this device created was used, and by which client (`PairingStatus`); `404` for an unknown ID or any other pairing; `403` for any other client key, before the pairing is looked up. See [Whether a code was used](#whether-a-code-was-used). |
| `GET /api/v1/client` | client key | The calling client's registration, including whether it is an admin device. |
| `PUT /api/v1/client/push-target` | client key | Sets the push target (`{"provider", "token"}`). `200` with the client. |
| `DELETE /api/v1/client/push-target` | client key | Removes the push target. Idempotent. `200` with the client. |
| `PUT /api/v1/client/push-preferences` | client key | Replaces the push preferences (`{"enabled", "minimumSeverity", "mutedCategories", "mutedProducerIds"}`, each optional). `200` with the client. |
| `GET /api/v1/client/push-config` | client key | The options an app needs to set up push with the server's provider, `{"provider", "options"}` (see [Push client options](#push-client-options)); `404` if the operator configured none. |
| `GET /api/v1/client/devices` | admin device's client key | Every client, as `GET /api/v1/admin/clients` lists them; `403` for any other client key. See [Device management from an admin device](#device-management-from-an-admin-device). |
| `POST /api/v1/client/devices/{id}/admin` | admin device's client key | Makes the client an admin device. `200` with the client (`ManagedClient`); `409` if it is revoked; `403` for any other client key. |
| `POST /api/v1/client/devices/{id}/revoke` | admin device's client key | Revokes a client that is not an admin. `200` with the client (`ManagedClient`), idempotent; `409` for an admin, the caller included; `403` for any other client key. |
| `DELETE /api/v1/client/devices/{id}` | admin device's client key | Deletes a revoked client, an admin or not. `204`; `409` if it is not revoked; `404` for an unknown ID; `403` for any other client key. |

The management paths behave like producer management: `404` for every path
while no admin token is configured, `404` for unknown IDs, and `400` for
invalid bodies with the usual violations. See
[development.md](development.md#clients) for curl examples.

The two `GET` management paths add `pushStatus` to each client (schema
`ManagedClient`), so the operator can see why a device got no push without
reading metrics or logs:

```json
"pushStatus": {
  "lastSuccess": {"at": "2026-09-27T10:00:02.123456Z", "eventId": "01997d5e-..."},
  "lastFailure": {"at": "2026-09-27T09:12:40.654321Z", "eventId": "01997d4a-...",
                  "result": "TRANSIENT_FAILURE"},
  "pendingRetries": 0
}
```

`lastSuccess` is the last push the provider accepted and `lastFailure` the
last one that failed, each `null` until there is one; `result` is
`UNSUPPORTED_PROVIDER`, `INVALID_TARGET`, `TRANSIENT_FAILURE` or
`PERMANENT_FAILURE` (see [Push delivery](#push-delivery)), never the token.
`pendingRetries` counts the client's pushes waiting to be sent again. Only
the latest results are kept, not a history (see
[Push dispatch](#push-dispatch)); revoking a client keeps them, and
deleting it removes them. The event
may have been deleted since by [retention](#retention). A client never
reads its own results: `/api/v1/client` and the other paths return `Client`,
without `pushStatus`.

### Schema

`V4__create_clients.sql` creates `clients`: `id`, `name`, `key_hash` (exactly
32 bytes), `created_at`, `revoked_at`, and `push_provider`, `push_token`,
`push_updated_at`, which are either all set or all `null`. A check constraint
forbids a push target on a revoked client. `V7__add_client_push_preferences.sql`
adds `push_enabled`, `push_minimum_severity`, `push_muted_categories`
(`text[]`) and `push_muted_producers` (`uuid[]`), with defaults that push
every event, so existing clients keep receiving everything; check constraints
allow only known severities and categories and at most 100 producers.
`V10__create_pairings.sql` creates `pairings`: `id`, `code_hash` (exactly 32
bytes, unique), `client_name`, `created_at` and `expires_at`, which must be
later than `created_at`. `V15__add_pairing_redemption.sql` adds
`redeemed_at` and `redeemed_by` (the client the code registered, deleted
with it), set together when the code is redeemed and `null` before. `V12__add_client_push_results.sql` adds each
client's last push results: `last_push_succeeded_at` and
`last_push_succeeded_event_id`, set together, and `last_push_failed_at`,
`last_push_failed_event_id` and `last_push_failed_result` (a failed
delivery result), set together; all are `null` for existing clients, so the
migration needs no operator action. The event IDs are not foreign keys, as
retention may delete the event. Changes
to one client lock its
row, so a revocation and a concurrent push-target update apply in order
rather than one overwriting the other.

### Logging

Registration, revocation, push-target and push-preference changes, and the
changes an admin device makes, are logged
at `INFO` with the client IDs, provider name and preferences only; never the key, its hash, or the push
token. Creating and redeeming a pairing are logged at `INFO` with the pairing
and client IDs, never the code. Rejected client keys and pairing codes are
logged at `DEBUG` like producer keys.

## Push delivery

> Status: the provider boundary, the `fcm` provider and event-triggered
> dispatch, filtered by each client's push preferences and with bounded
> retries of temporary failures, are implemented and tested with fakes.

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
| `TRANSIENT_FAILURE` | Unavailable, rate-limited, timed out; may succeed later. | Logs a warning and keeps the target; dispatch sends again later (see [Push dispatch](#push-dispatch)). |
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

### Push client options

An app needs its push provider's client options before it can get a push
token: for FCM, the identifiers of the operator's Firebase project and apps.
So that one app build works with any SignalHub server, the server can hand
them to its clients: `GET /api/v1/client/push-config` answers
`{"provider": "fcm", "options": {...}}` to any client key, and `404` when the
operator configured none (an app then needs its own, built in).

- **Provider-neutral.** The core sees a provider name and an opaque map of
  option names to strings (`PushClientOptions`, a CDI bean at the edge like a
  `PushProvider`). It never interprets them; their names and meaning are the
  provider's and the app's. At startup, options for a provider that is not
  enabled, or for two providers, stop the service, since an app would
  register a target that never receives anything. The log says
  `Push client options: served for fcm` or `none`.
- **FCM.** `SIGNALHUB_PUSH_FCM_CLIENT_OPTIONS_FILE` names a JSON object of
  names and strings: the same `firebase-options.json` the app is built with
  (`client/firebase-options.example.json`). SignalHub checks only that it is
  such an object (at most 32 options, names of letters, digits and
  underscores, non-empty values of at most 1024 characters), and refuses a
  file that looks like a service account key (`"type": "service_account"`,
  a `private_key`, or a `PRIVATE KEY` block). An invalid file stops startup;
  the message names the problem, never a value.
- **Only client-safe values.** Every client key can read the options, so
  they must be what any installed app carries anyway: Firebase's client
  identifiers and API keys, which identify the project and are not an
  authorization secret. Nothing able to send a push is ever served: the
  service account key stays in its own setting. A push token alone is never
  SignalHub authentication; setting a push target still needs the client
  key. If Firebase services beyond FCM are ever used, their security rules
  must stay restrictive, since the client API key is not a security
  boundary.

### Push dispatch

Every stored event is pushed to every client that has a push target and whose
[push preferences](#push-preferences) allow it. Preferences only suppress
pushes; the event itself is stored and listed either way.

```
 POST /api/v1/events ──one transaction──▶ events + push_dispatches (outbox)
                                              │ every 2 s
                                              ▼
                        EventPushDispatcher: claim oldest row ──▶ PushDelivery.deliver(client, message)
                                              │                     for each client with a push target
                                              │                     whose preferences allow the event
                                              ├─ delete the row; in the same transaction, a
                                              │  push_retries row per client whose send failed
                                              │  temporarily
                                              ▼
                        claim due retries ──▶ PushDelivery.deliver(client, message)
                                              └─ delete the row, or schedule the next attempt

 after each send: record the result on the client (last success or last failure)
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
  data.
- **Retries.** A send that fails temporarily (`TRANSIENT_FAILURE`: the
  provider is unavailable, rate-limited or timed out) is sent again, up to 5
  sends in all, after 30 seconds, then 2, 10 and 30 minutes; an outage of
  about 40 minutes is bridged. Each pending retry is a `push_retries` row
  (V8) per event and client, written in the transaction that completes the
  event's dispatch, and claimed like dispatch rows once due, so retries
  survive restarts. A retry reads the client's push target and preferences
  again: a client that was revoked, lost its target or muted the event
  meanwhile is not sent to. Retries are only for temporary failures; the
  other results are final (see [Push delivery](#push-delivery)).
- **Final failure.** After the last attempt the retry is dropped and a
  warning names the event and client (`Gave up the push of event ...`). No
  per-attempt record is kept (only each client's last results, above): the event stays in the inbox, where the client
  shows it on its next refresh, and a push that late would interrupt for
  little. A redispatched event does not reset a client's pending retry.
- **Each client's last results.** After each send, the dispatch and the
  retries record its result on the client (V12), in a transaction of its
  own: a delivered push overwrites the client's last success, any failure
  its last failure, both with the time and the event; a send that found no
  push target sent nothing and is not recorded. The count of pushes waiting
  for a retry is not stored but counted from `push_retries` when the
  management API is read. This is what
  [the management API](#client-api) shows; it is not a history. Recording
  never changes delivery: it happens after the send, and a failure to
  record is logged as a warning (`Could not record the push result ...`)
  and ignored, so the push is neither failed nor sent again, and retries
  are scheduled as before.
- **The push.** The event's title, its message shortened to 500 characters
  (providers limit payloads; FCM to 4 KiB), and data `eventId`, `category`
  and `severity`. It is a signal to look: the client fetches the event by ID.
- **Interval.** `signalhub.push.dispatch.interval`
  (`SIGNALHUB_PUSH_DISPATCH_INTERVAL`, default `2s`) is how often the
  dispatcher looks for new rows, and so the longest a push waits.
- Deleting an event (only [retention](#retention) does; the API cannot)
  drops its pending push and retries with it.

The push token never appears in logs:
providers must keep it out of outcome details, and an exception from a
provider is logged by type only.

## Client application

> Status: implemented in `client/`: setup by [pairing](#pairing) or with a
> client key, push
> registration and reception, the inbox and event details (including
> opening an event's [link](#link)), [read state](#read-state), and
> [push preferences](#push-preferences).

**Technology: Flutter**, chosen by the maintainer for roadmap R9. One Dart
codebase targets Android and iOS. Other platforms Flutter supports (web,
desktop) are possible later but not built or tested now.

The app is a client like any other: it uses only the public HTTP API with its
client key, and the backend knows nothing about Flutter, Android or iOS.

```
 ┌───────────────────────── client/lib ─────────────────────────┐
 │ ui (setup, inbox) ─▶ AppController ──▶ SignalHubApi ──HTTPS──▶ backend
 │                          │                                   │
 │                          ▼                                   │
 │               PushRegistration ──▶ PushService (port)         │
 └──────────────────────────────────────────│───────────────────┘
                                             ▼
                          FirebasePushService (adapter) ◀── FCM / APNs
```

- **Provider-neutral core.** `PushService` is the app's push port, mirroring
  the backend's `PushProvider`: a provider name, an opaque token, token
  refreshes, and received pushes as `PushNotice` (title, body, event ID). The
  controller, the push registration and the UI depend only on it.
  `FirebasePushService` is the only Dart code that imports Firebase; its
  provider name `fcm` matches the backend's provider.
- **Registration.** The setup screen offers [pairing](#pairing) first: the
  owner scans the pairing URI's QR code with the camera or pastes the URI,
  and the app redeems the code at the URI's server
  (`POST /api/v1/pairing`), which registers the installation as a new client
  and answers its key. The camera permission is asked for only when the
  scanner opens; a QR code that is not a pairing URI, an expired or used
  code (`401`) and an unreachable server (named, since the address comes
  from the operator's `SIGNALHUB_PUBLIC_URL`) each get their own message.
  Scanning uses `mobile_scanner` (the camera and the platform's barcode
  reader, ML Kit on Android and Vision on iOS, all on the device); the
  scanner is injected, so tests replace the camera. Manual setup stays: the
  operator registers the installation (`POST /api/v1/admin/clients`) and the
  owner enters the server address and client key. The app checks a typed
  key with `GET /api/v1/client` before saving it; a redeemed key needs no
  check, the redemption having answered the registration. Either way, it
  then asks for notification permission and sets its push
  target with `PUT /api/v1/client/push-target`, again on every start and
  whenever the provider issues a new token. Disconnecting removes the target
  (`DELETE`), deletes the provider token and forgets the key. A key the
  server no longer accepts sends the app back to setup.
- **Push options.** A build made with its own Firebase options
  (`--dart-define-from-file`) uses them, and they take precedence. A build
  without them reads the server's after setup, with the client key
  (`GET /api/v1/client/push-config`, see
  [Push client options](#push-client-options)), on every start and refresh
  before registering. The app starts Firebase only with options it has
  checked: provider `fcm`, every value it needs for its platform, a numeric
  sender ID and an app ID of this platform and sender
  (`1:<sender>:android:<hex>`); otherwise push stays off and the *This
  device* screen says why (none served, or not for this app). Firebase
  starts once per process, so options that change afterwards (another
  server, or the operator replaced them) register nothing until the app is
  restarted, and the app says so. The options are not stored; a start that
  cannot reach the server tries again on the next refresh.
- **Credentials.** The server address and client key are kept in the
  platform's secure storage (Keychain on iOS, Keystore-backed encryption on
  Android) and never logged.
- **Reception.** In the background, the operating system shows the
  notification from the push's title and body. On Android it is in the app's
  *Events* notification channel, at high importance so that it pops up; the
  owner can change that channel in the system settings. In the foreground,
  and when a notification opens the app, the push becomes a `PushNotice` and
  the app re-reads the inbox from the server: a push is a signal to look, so
  a push delivered twice (delivery is at least once) changes nothing.
  Tapping a notification also opens its event (by the push's `eventId`),
  including the notification that started the app. Pushes shown in the
  background never reach the app, so it also re-reads the inbox whenever it
  returns to the foreground.
- **Inbox.** The home screen lists events, newest first, from
  `GET /api/v1/events`, 30 per page. The next page is read with the previous
  page's `nextCursor` when the owner scrolls near the end; a pull to refresh
  starts again from the first page, and an older page still in flight is
  then dropped rather than appended out of order. Failures show a message
  with a retry; the rows already read stay. While the server does not answer
  at all (unreachable or timed out), that is the one message shown: push
  registration waits for the next refresh that reaches the server, and a
  push status such as a failed registration is shown only while the server
  answers. Each row shows the title,
  category, severity, producer name and `createdAt`, with an icon for the
  category and a color for the severity; they depend on nothing but these
  generic fields. The time is always shown in full; a long producer name
  gives way instead. An event with a [link](#link) has a small link icon;
  tapping the row still opens the event, not the link.
- **Inbox filters.** A filter button in the app bar opens a sheet with an
  *Unread only* switch and chips for producers, categories and severities;
  each change applies at once. The server applies them, through the
  listing's `read=false`, `producerId`, `category` and `severity` parameters
  (combined as the [listing](#listing-events) combines them), on the first
  page, on older pages with the same cursor rules, and on every refresh,
  including those after a push or a return to the foreground. Changing them
  reads the inbox again from the newest page and drops a page still in
  flight. While any filter is on, a bar above the inbox names each one and
  *Clear* removes them all with one tap; an empty result says that no event
  matches. The filters are kept only while the app runs: they are not
  remembered on the device, so the inbox always starts with every event and
  never hides new events behind a filter set days ago (the server keeps no
  per-client inbox state either). Client keys cannot list producers, so the
  producers offered are those of the events the inbox has read since the
  app connected, by name, including those a filter now hides; a producer
  appears once one of its events has been listed. An event read while shown
  in the unread-only view stays, shown as read, until the inbox is read
  again. The app bar's unread count is always the server's count of every
  unread event. *Mark all as read* is offered with *Unread only* but not
  with a producer, category or severity filter, since it would also mark
  events the filter hides. A server older than v2.5.0 ignores `read`
  (unknown query parameters are ignored), so the app also leaves out any
  read event a page brings in the unread-only view; a page with none left
  just reads the next one.
- **Event details.** Every field the API returns: title, message, category,
  severity, producer, context, `occurredAt`, `createdAt`, ID, and the
  metadata as indented JSON, shown as the producer sent it and never
  interpreted. An event opened from the inbox needs no request; one opened
  from a notification is read with `GET /api/v1/events/{id}` unless the
  inbox already has it, and an unknown ID says so.
- **Opening a link.** An event with a [link](#link) shows it among its
  fields and offers *Open link*, labelled with text beside its icon, which
  hands it to the platform with `url_launcher` to open outside the app: in
  the system browser, or in the app the platform assigns to the address
  (Android lists `http` and `https` `VIEW` intents under `<queries>`, as
  package visibility requires). There is no browser inside the app. A link
  no app opens leaves the owner on the event with a message. A tapped
  notification opens the event, never the link, so a link is only opened
  after the owner has seen the event it belongs to. The app accepts only
  what the server accepts, an absolute `http` or `https` URL with a host;
  any other value is ignored and the event is shown without a link, as are
  events from a server older than v2.3.0, which have no `link` field. The
  opener is injected, so tests replace the platform.
- **Read state.** The app shows the server's [read state](#read-state), so
  it is the same on every client. Unread rows have a bold title and a dot,
  and the app bar shows the unread count from
  `GET /api/v1/events/unread-count`, read with every inbox reload (also
  after a push), so it counts events on pages not read yet. Opening an
  event, from the inbox or a notification, marks it read
  (`PUT /api/v1/events/{id}/read`); if that fails the event stays
  unread, a message on the event screen says so without blocking it, and
  it is marked the next time. The event screen shows the state
  the server last returned (the answer to marking it read on opening, then
  to each change), and its one action, labelled with text beside its icon,
  follows it: *Mark as read* (`PUT`)
  while the event is unread, which stays on the event, and *Mark as unread*
  (`DELETE`) once it is read, which returns to the inbox. A failed change
  says why and leaves the state and the action as they were. *Mark all as read* sends the
  newest event shown as `through` (`POST /api/v1/events/read`), so events
  that arrived since stay unread; older events not paged in yet are read
  too, as the owner asked for everything up to that point.
- **Push preferences.** A *Notifications* screen sets this installation's
  [push preferences](#push-preferences): pause, minimum severity, and a
  switch for each category and each producer. Every change is saved at once
  with `PUT /api/v1/client/push-preferences`, sending all of them (the
  server replaces them), and the screen then shows what the server stored;
  a failed change says so and leaves the switches as they were. Client keys
  cannot list producers, so the producers offered are those of the events
  the inbox has read since the app connected, by name; a muted producer with no event there is listed by ID so
  it can be unmuted. Severities and categories are sent back as the server
  sent them, so values added in a later backend release survive a change. A
  server without push preferences (older than the app) is reported instead
  of the screen.
- **This device.** A screen from the inbox menu shows the installation's
  name, server and push status, and which build the app is: "SignalHub
  X.Y.Z" for an app a release built, "SignalHub development build" for any
  other, and "Commit" with the first 7 characters of the commit it was built
  from, or "Commit unknown" (see [Version](#version)).
- **Managing devices.** On an [admin device](#admin-devices) (its
  registration says `admin`), the *This device* screen also lists every
  device with `GET /api/v1/client/devices`, read when the screen opens and
  when it is pulled down: active devices first, each with its name and
  whether it is this device, an admin or revoked. A device that is neither
  an admin nor revoked offers *Make an admin* and *Revoke*, each after a
  confirmation ([Device management from an admin device](#device-management-from-an-admin-device));
  admins, this device included, offer neither, as the server would refuse
  them. A revoked device, an admin or not, offers *Delete*, after a
  confirmation, with `DELETE /api/v1/client/devices/{id}`
  ([Deleting a revoked client](#deleting-a-revoked-client)); an active
  device offers none, since it must be revoked first. The list shows each
  change as the server returned it, and a deleted device leaves it; a
  refused change says why and re-reads the list. A `404` for a delete
  re-reads the list too: a device no longer listed was deleted meanwhile
  (by the operator or another admin device) and is gone, while one still
  listed means a server released before deleting devices (older than
  v2.12.0), which has no such route; so does a `405`. The app then says the
  server cannot delete devices and stops offering *Delete*, which is shown
  until that first try because the server does not say which endpoints it
  has, and that try changes nothing. It lives on *This device*, not in
  a tab of its own: the app has no tabs, managing devices is occasional,
  and ordinary devices would never use one. A `403` from the device
  endpoints, or a registration read since without admin rights, says "This
  device is no longer an admin device" in place of the list and the app
  stops offering it. Devices that are not admins, and servers without
  admin devices (no `admin` field) or without the device endpoints (`404`
  for the listing), show nothing new. Renaming and taking admin rights away
  stay on the [admin page](#the-admin-page).
- **Connecting a device.** Above the list, an admin device offers *Connect
  a device*: it asks for the new device's name, creates a pairing code with
  `POST /api/v1/client/pairings`
  ([Pairing from an admin device](#pairing-from-an-admin-device)) and shows
  it as the admin page does: the pairing URI as a QR code, a countdown to
  its expiry ("Expires in 9:59. It works once."), which hides the code once
  it has expired, and the URI as text with *Copy link*, to send to whoever
  sets up the new device. It never pairs an admin device; the new device
  can be made one from the list once it has paired. The QR code is drawn by
  the app itself with the pure-Dart [`qr`](https://pub.dev/packages/qr)
  package, black on white with a quiet zone whatever the theme. When the
  server has no public address (`uri` is `null`), the app builds the same
  URI from the address it reaches the server at. The code is kept in memory
  only while the screen shows it, and the device list is read again when
  the screen closes. A `403` says "This device is no longer an admin
  device" as for the list; a server without the endpoint (`404`) says it
  cannot create pairing codes from a device, and the app stops offering it.
- **Events.** The app maps the API's events to a typed model. A category or
  severity added in a later backend release maps to *unknown* rather than
  failing, so older apps keep working (see
  [Category and severity](#category-and-severity)). Metadata stays opaque.
- **Platform edge.** Android and iOS specifics stay in `client/android` and
  `client/ios`: the app ID `io.github.rodrigofabreu.signalhub`, the
  notification permission, the iOS push entitlement and background mode, and
  plain HTTP only for debug builds (Android) or local addresses (iOS).
- **Firebase configuration.** The owner's Firebase project is passed at build
  time (`--dart-define-from-file`), never committed. A build without it runs
  without push, which is how CI and the tests build it. The backend can
  already serve these options ([Push client options](#push-client-options));
  the app starts using them in R23b.
- **Tests.** Unit and widget tests run against an in-memory fake of the
  client API (`MockClient`) and a fake `PushService`; no device, network or
  credentials. CI also compiles the Android and iOS apps.

## Producer SDK and CLI

> Status: implemented in `sdk/python/`: a Python package and the
> `signalhub send` command. Usage is in
> [`sdk/python/README.md`](../sdk/python/README.md).

The SDK is a convenience for producers, not part of the contract: it calls
`POST /api/v1/events` like any other producer, with no access to backend
internals, and everything it does is documented as plain HTTP too.

- **Python first.** Scripts, CI jobs and small home servers usually have
  Python, and one package gives both a library and a command.
- **Standard library only** (`urllib`, `json`, `argparse`), Python 3.10 or
  later: installing it adds no dependencies to a producer's environment. It is
  not published to PyPI; each release attaches its wheel and source archive,
  built with the release's version, which `signalhub --version` and the
  package's metadata report (see [Version](#version)).
- **Configuration** from `SIGNALHUB_URL` and `SIGNALHUB_API_KEY` (or
  `SIGNALHUB_API_KEY_FILE`). The command also takes `--url` and
  `--api-key-file`, but no option for the key itself, which would show in
  process lists and shell history.
- **The server validates.** Category and severity are normalized for
  convenience (case, `-` for `_`) but not checked against a local list, so an
  older SDK can send values a newer server adds. The server's violations are
  reported as they are. Only a timestamp without an offset is refused
  locally, since it cannot be sent unambiguously.
- **Errors say whether to retry.** The command exits `1` when the event or key
  was rejected, `2` on a usage or configuration error, and `3` on a
  temporary failure (unreachable, timeout, `429`, `5xx`); the library raises
  matching exceptions with a `temporary` flag. It does not retry by itself,
  so the caller decides how long to keep trying; with an idempotency key
  (`--idempotency-key`, `idempotency_key=`) a retry never stores the event
  twice (see [Idempotent publishing](#idempotent-publishing)).

## Integration examples

> Status: implemented in `examples/`, see
> [`examples/README.md`](../examples/README.md).

The examples show that unrelated producers fit the one generic contract:
a shell wrapper for any command, a disk-usage monitor, a GitHub Actions
workflow, a coding-agent hook (human gates and completions) and a
usage-threshold monitor. Each is an ordinary producer at the edge, with its
own API key: it maps its states onto `category` and `severity`, names its
subject in `context` and puts its details in opaque `metadata`. Nothing in
the backend, the database or the client app knows about any of them, and
they depend only on the public HTTP API, directly with `curl` or through the
Python package.

They are not a supported product surface: owners copy and adapt them, so
they are not versioned or installed like the SDK. Tests run each one against
a fake events endpoint, and the Compose smoke test runs them against the
real backend.

## Operations

### Logs

The backend logs to the console (standard output), where Docker and Compose
collect it. Credentials never reach the logs (see the Logging sections of
[Producers](#logging) and [Clients](#logging-1)).

- **Format.** Plain text by default, for reading. With
  `SIGNALHUB_LOG_JSON=true`, every record is one JSON object per line
  (Quarkus `quarkus-logging-json`: `timestamp`, `level`, `loggerName`,
  `message`, thread, host and, for errors, the exception), for log collectors
  such as Loki, Elasticsearch or a cloud log service. Collecting and keeping
  logs is the operator's choice, not part of SignalHub.
- **Levels.** `INFO` by default; the standard Quarkus variables change them,
  for example `QUARKUS_LOG_LEVEL=DEBUG` or
  `QUARKUS_LOG_CATEGORY__IO_GITHUB_RODRIGOFABREU_SIGNALHUB__LEVEL=DEBUG` for
  SignalHub only (rejected credentials are logged at `DEBUG`).
- **Startup summary.** Once started, the backend logs one `INFO` line with
  its release (see [Version](#version)) and the effective configuration, so
  the log alone tells which release, database, features and resources a
  running service uses:

  ```text
  SignalHub 1.2.3 (commit 0123456789abcdef0123456789abcdef01234567); Configuration: profile prod; database jdbc:postgresql://postgres:5432/signalhub as signalhub; management API enabled; FCM credentials file /run/secrets/fcm.json; FCM client options file /run/config/firebase-options.json; push dispatch every 2s; event retention off (events are kept forever); JSON logs off; Java 25.0.4.1+1-LTS, 2 CPUs, max heap 768 MiB
  ```

  It names settings, never secret values: the admin token appears only as
  enabled or disabled, the database password never, and the database URL
  without its parameters or user information, which could carry
  credentials. `Push providers: [...]` follows it, naming the providers
  actually active.
- **Configuration errors stop startup** with a message naming the setting to
  fix: a missing database, a short admin token, an unreadable FCM key file,
  or a value of the wrong type (for example `SIGNALHUB_LOG_JSON=yes`).

### Version

SignalHub has one version, the repository's release tag. Every release
publishes the backend as a multi-platform image (`linux/amd64` and
`linux/arm64`), `ghcr.io/rodrigofabreu/signalhub:X.Y.Z`, built from the
tagged commit (see [development.md](development.md#release-process)), and
attaches the deployment files that run it, `compose.yaml` naming the image by
version and digest (see [deployment.md](deployment.md#deployment-files)). The
release bakes its version and commit into the image, and the backend
reports them:

- at `/q/info`, beside health and metrics, and so not forwarded by the
  proxy; the product API has no version endpoint:

  ```json
  {"signalhub": {"version": "1.2.3", "revision": "0123456789abcdef0123456789abcdef01234567"}, "java": {...}, "os": {...}}
  ```

- at the start of the [startup summary](#logs);
- in the image's OCI labels `org.opencontainers.image.version`, `revision`,
  `created` (the commit's time) and `source`.

Any build the release did not make, such as `docker compose up --build` or
`./mvnw quarkus:dev`, reports version `development` and no commit, and
calls itself a development build in the startup summary, so it never passes
for a release. The version fields in the sources (`backend/pom.xml` and the
others) are development placeholders that no release rewrites. The values
come from `SIGNALHUB_VERSION` and `SIGNALHUB_REVISION`, which only the
release's image build sets; they are not settings for operators.

The release also attaches the Python SDK and command (see
[Producer SDK and CLI](#producer-sdk-and-cli)) as a wheel and a source
archive, built from the tagged commit with the release's version in place of
the placeholder `0.0.0.dev0` of `sdk/python/pyproject.toml`:
`signalhub --version` prints `SignalHub 1.2.3`, and the package's metadata
carries `1.2.3`. A package built any other way keeps the placeholder and
prints `SignalHub development build`.

The app shows its build on its *This device* screen (see
[Client application](#client-application)). It takes two values at build
time as `--dart-define`s, never the placeholder `version:` of
`client/pubspec.yaml`: `SIGNALHUB_REVISION`, the commit, which the build
commands in [client/README.md](../client/README.md#build-identity) pass for
every build, and `SIGNALHUB_VERSION`, which only a release's own app build
sets: the release's `SignalHub-X.Y.Z.apk`, whose Android `versionName` is
the version too (see
[client/README.md](../client/README.md#install-a-release)). So an app built
locally, even from a release's tag, says "SignalHub development build" and
names its commit; one built without the commit, such as by a plain
`flutter run`, says "Commit unknown".

### Metrics

`/q/metrics` serves metrics in the Prometheus text format (and OpenMetrics
when the scraper asks for it), through Micrometer, the Quarkus standard. It is
what an operator reads to see health, failures and delivery without a
debugger; scraping and dashboards are the operator's choice (for example
Prometheus and Grafana), not part of SignalHub.

- **Built in:** HTTP requests by method, templated path and status
  (`http_server_requests_seconds`; `/q/` paths are not measured), the JVM
  (memory, garbage collection, threads), the process, and the database
  connection pool (`agroal_*`).
- **SignalHub's own:**

  | Meter | Type | Meaning |
  |---|---|---|
  | `signalhub_events_published_total` | counter | Events stored and acknowledged; a repeat with an idempotency key stores nothing and is not counted. |
  | `signalhub_events_deleted_total` | counter | Events deleted because they were older than the [retention](#retention) period. |
  | `signalhub_push_deliveries_total{result}` | counter | Pushes to one client, by `result`: `delivered`, `no_target`, `unsupported_provider`, `invalid_target`, `transient_failure`, `permanent_failure` (see [Push delivery](#push-delivery)). Retries count again. |
  | `signalhub_push_retries_abandoned_total` | counter | Pushes given up after the last attempt failed temporarily (see [Push dispatch](#push-dispatch)). |
  | `signalhub_push_dispatch_pending` | gauge | Events whose push is not dispatched yet. |
  | `signalhub_push_retries_pending` | gauge | Pushes to one client waiting to be sent again, due or not. |

  The two gauges are counted by each dispatcher run (every
  `signalhub.push.dispatch.interval`, 2 s by default), so a scrape
  never queries the database. A dispatch backlog that keeps growing means the
  dispatcher is stuck; many `transient_failure` results mean the provider is
  unreachable.
- **Nothing identifying.** Tags are bounded, generic values. Meters never
  carry credentials, push tokens, event, producer or client IDs or names,
  or event content; request paths are the endpoint templates
  (`/api/v1/events/{id}`), never the IDs in them.
- **Exposure.** Like health, `/q/metrics` needs no credential: it holds
  counts, not data, and scrapers rarely authenticate. Compose publishes the
  port on `127.0.0.1` only, and its TLS proxy forwards only `/api/` (see
  [deployment.md](deployment.md#network-exposure)).

### Retention

Events are kept forever by default: upgrading never deletes history. An
operator who wants storage to stop growing sets a retention period, and
events older than it are deleted.

- **Setting.** `SIGNALHUB_EVENTS_RETENTION` (`signalhub.events.retention`), a
  duration such as `365d` or `90d`. At least one day (`1d`): anything
  shorter stops startup, so a mistyped unit (`1h`) cannot empty the inbox,
  and events live long enough for the owner to see them and for their
  pushes to be retried. Unset or empty keeps events forever. The startup
  summary names it (`event retention 365d`).
- **Age.** Measured from `createdAt`, the server's clock, never the
  producer's `occurredAt`. Every event is treated alike: read or unread,
  whatever its producer, category or severity. Events are a history, not a
  to-do list; an operator who wants some kept longer chooses a longer
  period.
- **Deletion.** Every hour, starting a minute after startup, a job deletes
  the expired events, oldest first, 1000 per transaction through the
  `(created_at, id)` index (V3), so a large backlog after enabling
  retention never holds long locks. An event's pending push and retries go
  with it (their foreign keys cascade); producers and clients are
  untouched. An `INFO` line reports how many events were deleted, and
  `signalhub_events_deleted_total` counts them (see [Metrics](#metrics)).
- **Consequences.** A deleted event is gone: `GET /api/v1/events/{id}` and
  marking it read answer `404`, and it drops out of the listing and the
  unread count. Cursors stay valid, since they carry a position rather than
  an event. PostgreSQL reuses the freed space for new events (autovacuum),
  so the database stops growing without a manual `VACUUM FULL`; backups
  taken before the deletion still hold the events.

### Backup and restore

PostgreSQL holds all of SignalHub's state: events and their read state,
producers and key hashes, clients with their push targets and preferences,
and pending pushes. The backend keeps nothing else, so a backup of the
database is a backup of SignalHub. The commands below are for the Compose
stack, run next to `compose.yaml`; the CI smoke test runs the same ones.

- **Back up** with `pg_dump` inside the database container, which matches
  the server's version. It reads one consistent snapshot while the backend
  keeps running, so there is no downtime:

  ```sh
  backup=signalhub-$(date +%F).dump
  docker compose exec -T postgres sh -c \
    'pg_dump --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --format=custom' \
    > "$backup"
  docker compose exec -T postgres pg_restore --list < "$backup" > /dev/null   # fails if unreadable
  ```

  The custom format is compressed and restored with `pg_restore`. Schedule
  it (for example a daily cron job on the host), keep several copies, and
  store them off the machine.
- **What a backup holds.** Everything in the database, including the
  schema's Flyway history. Not included: `.env` (database password, admin
  token, settings) and the FCM service account key file, which are kept
  where the operator keeps secrets (see
  [deployment.md](deployment.md#secrets)). A backup holds key hashes, never keys,
  so producer and client keys keep working after a restore; but it holds
  push tokens and every event, so store it as privately as the database.
- **Restore** into an empty database, the whole database at once. On a
  new machine, or to replace the current data (this deletes it: back it up
  first):

  ```sh
  docker compose down
  docker volume rm signalhub_postgres-data # the database volume only
  docker compose up --wait postgres        # an empty database, without the backend
  docker compose exec -T postgres sh -c \
    'pg_restore --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --no-owner --no-privileges --exit-on-error --single-transaction' \
    < signalhub-2026-09-25.dump
  docker compose up --wait                 # the backend applies any newer migrations
  ```

  The backend must not start before the restore, or its migrations would
  fill the empty database first. The restore runs in one transaction, so
  it applies completely or not at all; restoring into a database that
  already holds SignalHub's tables fails and changes nothing.
  `--no-owner` lets a different database user (`SIGNALHUB_DB_USERNAME`)
  own the restored tables.
- **Versions.** Restore with the same or a newer SignalHub release: the
  backend migrates an older schema forward at startup, as on any upgrade.
  Restore into the same or a newer PostgreSQL major version; a dump and
  restore like this one is also how the database moves to a new PostgreSQL
  major version, whose data directory the old volume cannot be used with.
- **After a restore** everything is as it was at the backup: events
  published since are gone (producers do not resend them), and pushes that
  were pending then may be sent again (delivery is at least once).

### Resources

The CI smoke test runs the whole Compose stack with the limits below;
storage was measured on PostgreSQL with SignalHub's schema.

- **Memory.** The backend is a JVM whose heap is 75 % of the container's
  memory limit (`-XX:MaxRAMPercentage=75`, see
  [Backend implementation decisions](#backend-implementation-decisions)),
  or of the host's memory without one. For a personal service, 512 MiB for
  the backend and 256 MiB for PostgreSQL are enough. Without limits, the
  JVM sizes its heap from the whole host and may hold more memory than it
  needs, so set them on shared hosts, in a git-ignored
  `compose.override.yaml` next to `compose.yaml`:

  ```yaml
  services:
    backend:
      mem_limit: 512m
      cpus: 1
    postgres:
      mem_limit: 256m
  ```

  The startup summary shows the resulting heap (`max heap ... MiB`) and
  CPUs, and `/q/metrics` the JVM's memory use (`jvm_memory_used_bytes`).
- **CPU.** Idle except for the push dispatcher's short query every
  `SIGNALHUB_PUSH_DISPATCH_INTERVAL`; one CPU is enough. With fewer CPUs
  the JVM starts more slowly.
- **Storage.** A typical event (a title, a few hundred characters of
  message, a few metadata fields) takes about 1 KiB in PostgreSQL, indexes
  included; one at the size limits (4000-character message, 16 KiB of
  metadata) at most about 32 KiB, less once PostgreSQL compresses it. A thousand typical events a day is about
  350 MiB a year, and a compressed backup is smaller still. Other tables stay
  small: producers, clients, and pushes that are pending or waiting for a
  retry. Set a [retention](#retention) period to stop growth, and check the
  size with:

  ```sh
  docker compose exec postgres sh -c \
    'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --command "SELECT pg_size_pretty(pg_database_size(current_database()))"'
  ```

## Likely components

| Component | Direction | Responsibility |
|---|---|---|
| Backend | Java 25, Quarkus (see [Backend platform](#backend-platform)) | Producer API, validation, persistence, dispatch, client-facing API |
| Database | PostgreSQL | System of record for events, producers, devices, delivery state |
| Push | A push provider, likely Firebase Cloud Messaging | Transport to devices only, carrying minimal payloads |
| Clients | Flutter app for Android and iOS (see [Client application](#client-application)); other clients (CLI, web) may follow | Device registration, notifications, event browsing |
| Producer SDK/CLI | Python package and command in `sdk/python/` (see [Producer SDK and CLI](#producer-sdk-and-cli)) | Thin client over the public HTTP API |
| Deployment | Docker, Docker Compose, on x86-64 and ARM64, with Caddy as the TLS reverse proxy (see [deployment.md](deployment.md)) | Reproducible self-hosted deployment |

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
| Language and runtime | Java 25 (LTS) |
| Framework | Quarkus |
| HTTP API | Quarkus REST (RESTEasy Reactive), JSON |
| Persistence | Hibernate ORM with Panache over PostgreSQL |
| Schema migrations | Flyway |
| Input validation | Jakarta Validation |
| API description | SmallRye OpenAPI |
| Health checks | SmallRye Health |
| Tests | JUnit 5, RestAssured, real PostgreSQL |
| Packaging | Docker image, run with Docker Compose; each release publishes it to GHCR and attaches the Compose files that run it (see [Version](#version)) |

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
  in a Maven stage and runs it on an Eclipse Temurin 25 JRE as a non-root
  user, with base images pinned by digest and `curl` added for the image's
  health check. Heap is sized from the container limit
  (`-XX:MaxRAMPercentage=75`). Native images are out of scope.
- **Configuration:** `application.properties` holds non-secret defaults.
  Dev and test get PostgreSQL from Quarkus Dev Services. The `prod` profile
  reads `SIGNALHUB_DB_URL`, `SIGNALHUB_DB_USERNAME`, and
  `SIGNALHUB_DB_PASSWORD`, and the service refuses to start without a
  database URL, because Quarkus would otherwise deactivate the datasource
  and report ready without a database.
- **Schema:** Flyway runs at startup in every profile from
  `classpath:db/migration`, with migration naming validated. The backend
  refuses to start, before migrating or validating, on a database holding a
  migration it does not have: a newer release migrated it, and this code
  was not written for that schema (`SchemaVersionGuard`, a Flyway
  callback; Flyway's own refusal advises a `repair` that would hide the
  newer changes). Hibernate's
  schema management is `none`. Tables are listed in
  `backend/src/main/resources/db/migration/README.md`.
- **Endpoints:** Quarkus's standard management paths under `/q/`:
  `/q/health/live` (liveness, no dependency checks), `/q/health/ready`
  (readiness, includes the PostgreSQL connection check), `/q/openapi`, and
  `/q/metrics` (see [Metrics](#metrics)).
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
- **Deployment:** `compose.yaml` runs the backend and PostgreSQL 18 with a
  named volume. The backend starts after the database is healthy and is
  itself health-checked through readiness. Its `proxy` profile adds Caddy
  as the TLS reverse proxy, chosen because it obtains and renews
  certificates itself with a few lines of configuration (`proxy/Caddyfile`);
  see [deployment.md](deployment.md).

## Compatibility

What SignalHub promises to keep working from one release to the next, and
what a release must mark as breaking (`!` in its title, see
[development.md](development.md#versioning)). From `1.0.0` a breaking
change bumps the major version; before it, it bumped the minor version.

**The public contract** is what producers, clients and operators depend on:

- the product HTTP API under `/api/v1/` (paths, methods, credentials, headers
  such as `Idempotency-Key`, status codes, request and response fields, the
  error body) and the event schema,
  as documented here and in the OpenAPI document;
- the category and severity values, key formats (`shpk1_`, `shck1_`) and
  cursor opacity;
- the management API under `/api/v1/admin/`;
- the data of a push message (`eventId`, `category`, `severity`, see
  [Push dispatch](#push-dispatch)), which the app reads;
- operator configuration: the variables in `.env.example`, the Compose
  services, volumes and profiles, and the documented backup, restore and
  upgrade procedures, the health endpoints and SignalHub's own meters
  (`signalhub_*`, see [Metrics](#metrics));
- the database: an upgrade migrates it forward with Flyway, keeping every
  stored event, key, client and preference;
- the `signalhub` command's options and exit statuses and the Python SDK's
  public names;
- the published backend image, `ghcr.io/rodrigofabreu/signalhub:X.Y.Z` for
  `linux/amd64` and `linux/arm64`, and the `signalhub` section of `/q/info`
  (see [Version](#version));
- a release's deployment files, `signalhub-X.Y.Z-deployment.tar.gz` and
  `SHA256SUMS`: their names and the files they hold (see
  [deployment.md](deployment.md#deployment-files)).

Not part of it: the database schema itself (only migrations touch it), the
backend's Java code, the built-in metrics of Quarkus and its libraries, log
text, and the rest of `/q/`.

**Compatible changes**, released as `feat` or `fix`:

- a new endpoint, a new optional request field or query parameter, a new
  response field;
- a new category or severity value;
- a new optional configuration variable whose default keeps the previous
  behaviour;
- a new migration that keeps existing data.

Every listing answers an object with its entries in `items`, never a bare
array, so that paging or other fields can be added compatibly.

**Breaking changes** need `!` and migration notes in the release: removing or
renaming anything above, making an optional field required, changing a
field's type or meaning, requiring a credential where none was needed, and
refusing a request that used to be accepted.

**Rules for readers.** So that compatible changes stay compatible, a client or
SDK built against one release must:

- ignore response fields it does not know;
- accept category and severity values it does not know: show the event
  anyway (the app shows "Other" and "Unknown") and keep such values when it
  writes them back (the app does, in push preferences);
- decide by the HTTP status and treat the error body as a description;
- not parse cursors or key secrets.

The app and the Python SDK follow these rules; the SDK passes category and
severity through without checking them, so it can publish values a newer
server adds. The server stays strict in the other direction: it rejects
unknown request fields and enum values with `400`, so a mistake is reported
instead of silently dropped. A producer that uses a newer field or value
against an older server therefore gets `400`, and must be upgraded after the
server, not before. `link` (v2.3.0) is such a field: an older server
rejects an event that has one. Unknown query parameters are ignored.

**Versioning of the API path.** `/api/v1/` changes only for a redesign that
cannot be made compatible; a breaking change within `v1` is released under
the rules above instead. Nothing is planned that needs `/api/v2/`.

## Cross-cutting principles

- **Durability first:** persist, then acknowledge, then deliver.
- **Idempotency:** producers may retry, so publishing with an idempotency key
  stores an event once however often it is sent; see
  [Idempotent publishing](#idempotent-publishing).
- **Secrets from the environment:** credentials (the admin token, push-provider
  credentials, database password) come from runtime configuration, never from
  the repository. Producer API keys are generated by the server and stored
  only as hashes.
- **Versioned contracts:** the producer API and event schema are public
  contracts. Breaking them is a breaking change under the release policy in
  [development.md](development.md).

## Open questions

These are deferred until the relevant implementation work:

- How a client obtains its key without the operator copying it by hand
  (for example a pairing flow), once a client application exists.
- Time-based push rules such as quiet hours; which events are pushed is
  already decided per client by its [push preferences](#push-preferences).
- Whether further clients (web, desktop, CLI) are built, and with what.
