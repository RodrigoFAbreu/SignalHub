# SignalHub

A producer-agnostic personal notification platform.

Any system can publish generic events to SignalHub: autonomous agents, CI
pipelines, monitoring, homelab services, or one-off scripts. SignalHub persists
the events and delivers notifications about them to the owner's devices.
Producers share one generic event contract, and SignalHub has no special cases
for individual producers.

## Intended architecture

```
producers ──HTTPS──▶ backend (Quarkus + PostgreSQL) ──push──▶ clients
    ▲                                              ◀─HTTPS──
optional SDK/CLI
```

- **Backend:** Java 21, Quarkus (Quarkus REST, Hibernate ORM with Panache,
  Flyway, Jakarta Validation, SmallRye OpenAPI and Health), PostgreSQL
- **Push delivery:** a push provider, likely Firebase Cloud Messaging
- **Client app:** Flutter, one codebase for Android and iOS, with push
  through Firebase Cloud Messaging. The API is client-agnostic, so other
  clients (web, CLI) remain possible.
- **Producer client:** optional thin SDK/CLI over the HTTP API, in Python
- **Deployment:** Docker / Docker Compose

See [docs/architecture.md](docs/architecture.md).

## Status

Early development.

| Component | Status |
|---|---|
| Backend (`backend/`) | Quarkus service with PostgreSQL, Flyway, health checks, OpenAPI, Docker image and Compose. Generic event ingestion: `POST /api/v1/events` and `GET /api/v1/events/{id}`. Paginated, filterable event listing (the inbox): `GET /api/v1/events`. Read state shared by all of the owner's clients: mark events read or unread, one at a time or up to an event, and count unread events. Producer authentication with server-issued API keys, managed through an admin-token-protected API. Client registration: each client installation gets its own key for reading events and stores a provider-neutral push target. Push notifications: every published event is pushed, durably and at least once, with bounded retries of temporary failures, to every client with a push target whose push preferences allow it (paused, minimum severity, muted categories or producers), through Firebase Cloud Messaging (enabled by a service account key file) behind a provider-neutral boundary. Prometheus metrics at `/q/metrics`, including events published and push delivery results and backlog. Optional JSON logs for log collectors and a startup summary of the effective configuration, without secrets. An optional retention period after which old events are deleted. Documented, tested backup and restore of the database, and memory, CPU and storage guidance. |
| Client app (`client/`) | Flutter app for Android and iOS: connects to the server with a client key kept in secure storage, registers for push notifications (Firebase Cloud Messaging, configured with the owner's Firebase project at build time), and shows the inbox: every event, newest first, page by page, with each event's details, also opened by tapping its notification. Unread events and their count are shown; opening an event marks it read on every client, and events can be marked unread or all read. Push preferences for the device: pause, minimum severity, muted categories and producers. See [client/README.md](client/README.md). |
| Producer SDK/CLI (`sdk/python/`) | Python package and `signalhub send` command over the public HTTP API: configured with the server address and an API key from the environment or a file, arbitrary metadata, the server's validation errors printed, and exit statuses that tell rejected events from temporary failures. Standard library only. See [sdk/python/README.md](sdk/python/README.md). |

Run the backend with PostgreSQL:

```sh
cp .env.example .env   # set SIGNALHUB_DB_PASSWORD and SIGNALHUB_ADMIN_TOKEN
docker compose up --build --wait
curl http://localhost:8080/q/health/ready

# Register a producer; the response shows its API key once.
ADMIN_TOKEN=$(sed -n 's/^SIGNALHUB_ADMIN_TOKEN=//p' .env)
API_KEY=$(curl -s http://localhost:8080/api/v1/admin/producers \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "my-script"}' | jq -r .apiKey)

# Publish an event as that producer.
curl http://localhost:8080/api/v1/events -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"category": "INFO", "severity": "NORMAL", "title": "Hello"}'

# Register a client (an app installation); it reads events with its own key.
CLIENT_KEY=$(curl -s http://localhost:8080/api/v1/admin/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "my-laptop"}' | jq -r .clientKey)

# Or publish with the Python command (sdk/python/README.md).
pip install ./sdk/python
SIGNALHUB_URL=http://localhost:8080 SIGNALHUB_API_KEY=$API_KEY \
  signalhub send --category COMPLETED --severity NORMAL --title "Hello again"

# List events, newest first, as that client.
curl -s http://localhost:8080/api/v1/events -H "Authorization: Bearer $CLIENT_KEY"
```

The event model and API are described in
[docs/architecture.md](docs/architecture.md#events), and producers and API
keys in
[docs/architecture.md](docs/architecture.md#producers-and-authentication),
and clients in [docs/architecture.md](docs/architecture.md#clients).

See [docs/development.md](docs/development.md#backend) for dev mode, tests, and
configuration, and [docs/development.md](docs/development.md#client) for the
client app.

## Development philosophy

- **Trunk-based:** short-lived branches, squash-merged PRs, and a `main` that is
  always releasable.
- **Every commit on `main` is a release:** it is automatically tagged with a
  semantic version derived from its Conventional Commit title.
- **Vertical increments:** each change is complete, tested, and documented on
  its own.
- **Producer-agnostic core:** new needs become generic capabilities.

See [docs/development.md](docs/development.md) for the workflow and release
rules, and [CLAUDE.md](CLAUDE.md) for the rules that apply to all contributors,
human or agent.
