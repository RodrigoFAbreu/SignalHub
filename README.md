# SignalHub

A producer-agnostic personal notification platform.

Any system can publish generic events to SignalHub: autonomous agents, CI
pipelines, monitoring, homelab services, or one-off scripts. SignalHub persists
the events and delivers notifications about them to a mobile app. Producers
share one generic event contract, and SignalHub has no special cases for
individual producers.

## Intended architecture

```
producers ──HTTPS──▶ backend (FastAPI + PostgreSQL) ──FCM──▶ Android app
    ▲
Python SDK/CLI
```

- **Backend:** Python, FastAPI, PostgreSQL
- **Push delivery:** Firebase Cloud Messaging
- **Mobile:** Android, Kotlin, Jetpack Compose
- **Producer client:** Python SDK/CLI
- **Deployment:** Docker / Docker Compose

See [docs/architecture.md](docs/architecture.md).

## Status

Early development. The repository has its engineering baseline
(documentation, CI, and automated releases) and these components:

| Component | Status |
|---|---|
| Backend (`backend/`) | Runtime foundation: configuration, PostgreSQL, Alembic migrations, health endpoints, Docker Compose. Does not ingest events yet. |
| Mobile app | Not started |
| Producer SDK/CLI | Not started |

Quick start (requires Docker):

```sh
cp .env.example .env    # then set POSTGRES_PASSWORD
docker compose up --build --detach --wait
curl http://127.0.0.1:8000/health/ready
```

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
