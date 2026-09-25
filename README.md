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

Early bootstrap. The repository contains its engineering baseline:
documentation, CI, and automated releases. No product components exist yet.

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
