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
| Backend (`backend/`) | Runtime foundation: Quarkus service, PostgreSQL, Flyway, health checks, OpenAPI, Docker image and Compose. No product API yet. |
| Clients | Not started |
| Producer SDK/CLI | Not started |

Run the backend with PostgreSQL:

```sh
cp .env.example .env   # set SIGNALHUB_DB_PASSWORD
docker compose up --build --wait
curl http://localhost:8080/q/health/ready
```

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
