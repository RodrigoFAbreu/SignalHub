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

- `push` package: `PushProvider` port (`name()` + `send(message, token)`),
  provider-neutral `PushMessage` (event ID, category, severity, title,
  message) and `PushResult` (`DELIVERED`, `INVALID_TARGET`, `FAILED`)
- storing an event requests a push; the dispatcher runs after the commit, on
  one background thread, and sends to every push target whose provider is
  available (a provider is a CDI bean; names unique and validated at startup)
- `INVALID_TARGET` removes the push target unless the client replaced it;
  failures and provider exceptions are logged, not retried (R13)
- no concrete provider yet, and no schema or HTTP API change; a test-only
  recording provider stands in for real ones in tests

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

Goal: deliberately declare the first stable SignalHub contract.

Before `v1.0.0`, review:

- public REST API consistency
- authentication/key lifecycle
- event schema
- enum evolution strategy
- pagination
- migrations and upgrade path
- client/device lifecycle
- push semantics
- error formats
- configuration compatibility
- backup/restore
- deployment documentation
- security boundaries
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

After the push-provider abstraction (R7), the expected next milestone is:

**R8 - FCM delivery**

R8 adds an `fcm` `PushProvider` beside the R7 boundary, active only when its
credentials are configured from the environment. CI uses a local substitute;
proving delivery to a real device needs the maintainer's Firebase project
and credentials.

The orchestrator must first inspect `main`, releases and open pull requests to confirm this remains true.
