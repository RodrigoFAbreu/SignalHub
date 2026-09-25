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
- **Clients:** undecided. The API is client-agnostic, so Android, iOS, web,
  and CLI clients are all possible.
- **Producer client:** optional thin SDK/CLI over the HTTP API (for example in
  Python)
- **Deployment:** Docker / Docker Compose

See [docs/architecture.md](docs/architecture.md).

## Status

Early development.

| Component | Status |
|---|---|
| Backend (`backend/`) | Quarkus service with PostgreSQL, Flyway, health checks, OpenAPI, Docker image and Compose. Generic event ingestion: `POST /api/v1/events` and `GET /api/v1/events/{id}`. Paginated, filterable event listing (the inbox): `GET /api/v1/events`. Producer authentication with server-issued API keys, managed through an admin-token-protected API. No owner/client authentication or push delivery yet. |
| Clients | Not started |
| Producer SDK/CLI | Not started |

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

# List events, newest first, as the owner.
curl -s http://localhost:8080/api/v1/events -H "Authorization: Bearer $ADMIN_TOKEN"
```

The event model and API are described in
[docs/architecture.md](docs/architecture.md#events), and producers and API
keys in
[docs/architecture.md](docs/architecture.md#producers-and-authentication).

See [docs/development.md](docs/development.md#backend) for dev mode, tests, and
configuration.

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
