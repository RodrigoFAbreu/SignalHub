# Development

SignalHub uses lightweight trunk-based development. `main` is always
releasable, and **every commit on `main` is a release**.

## Branching

- Never commit directly to `main`.
- Work on short-lived branches off the latest `main`, named by intent, e.g.
  `feat/event-ingestion`, `fix/duplicate-delivery`, `docs/producer-api`.
- Keep branches small. Merge within days, not weeks. Rebase on `main` as needed.
- If the PR for a branch has been merged, start follow-up work from the latest
  `main`. Never add commits to a merged branch.

## Pull requests

Changes reach `main` only through pull requests, and PRs are **squash merged**.
One merged PR becomes one commit on `main`, and that commit is one release.

A PR is ready to merge when:

- it is one coherent, vertically complete change: working code, tests,
  configuration, and documentation together;
- CI is green: the **CI** workflow and the **PR title** check;
- the PR template is filled in, including release impact and
  compatibility/migration notes;
- `main` would be releasable immediately after the merge.

Do not merge partial scaffolding, disabled tests, or "fix it in the next PR"
changes. If a feature is too large for one PR, split it into increments that
each work on their own, and keep unfinished behaviour unreachable (for example,
not wired into routing or not exposed in configuration) rather than broken.

## PR titles are release commits

The squash commit subject is the PR title, so the title must be a
[Conventional Commit](https://www.conventionalcommits.org/):

```
<type>[(scope)][!]: <description>
```

Allowed types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`,
`ci`, `chore`, `style`, `revert`. Scopes are lowercase, e.g. `feat(api): ...`.
Mark a breaking change with `!`, e.g. `feat(api)!: require event ids`.

The **PR title** check validates the title and prints its release impact. It
uses the same code as the release workflow (`scripts/release/release.py`).

Only the title matters for versioning. A `BREAKING CHANGE:` footer in the PR
body is **not** read, because squash commit bodies vary with repository
settings and PR description text. Use `!` in the title.

## Versioning

Versions are `vMAJOR.MINOR.PATCH` git tags.

| Title | Version 1.0.0 or later | Before 1.0.0 (now) |
|---|---|---|
| `feat!:` / any `type!:` (breaking) | major | **minor** |
| `feat:` | minor | minor |
| `fix:` and all other types | patch | patch |

**Pre-1.0 rule:** SignalHub is in initial development. A breaking change bumps
the minor version (`0.4.2` → `0.5.0`), as SemVer allows for `0.y.z`. A `!`
never produces `1.0.0` by accident. This means a `0.x` minor release may be
breaking; read the release notes. Moving to `1.0.0` is a deliberate decision.
It is made in a PR that changes the release policy in
`scripts/release/release.py` and its tests, and updates this document.

The first release has no previous tag, so it is computed from `0.0.0`. A `feat:`
bootstrap PR releases `v0.1.0`.

## Release process

Releases are fully automated by `.github/workflows/release.yml`. There is no
release PR and no manual step.

On every push to `main`:

1. The CI workflow runs again on the merged commit.
2. If CI passes, `release.py next-version` finds the highest `vX.Y.Z` tag
   reachable from the commit and the unreleased commits since it. The next
   version is that tag bumped by the largest bump among those commits.
3. `gh release create` tags the commit and publishes a GitHub release with
   generated notes.

Normally exactly one commit is unreleased, so each merge gets its own release.
Release runs are serialized. If a run fails, or a queued run is superseded by a
newer merge, the next successful run releases everything unreleased together at
the newer commit. Nothing is skipped silently, and a commit that failed CI on
`main` is never tagged on its own. Re-running a release for a commit that is
already tagged does nothing.

If a non-Conventional subject reaches `main` (which is only possible if the
title check was bypassed), the release workflow counts it as a patch and emits
a warning. It does not block all future releases.

## Definition of a releasable `main`

Every commit on `main` must:

- pass all CI checks;
- build and run for every component that exists in the repository;
- contain no known-broken, half-wired, or placeholder behaviour reachable by
  users or producers;
- have documentation that matches actual behaviour;
- contain no secrets or environment-specific credentials;
- include migrations for any persisted data or configuration change it
  introduces.

## Local validation

CI runs the following. Run all of it before declaring work done.

```sh
# Lint and format (whole repository)
pip install ruff==0.16.9
ruff check .
ruff format --check .

# Release tooling
python -m unittest discover --start-directory scripts/release --verbose

# Backend tests (needs PostgreSQL, see "Backend" below)
(cd backend && uv sync --locked && uv run --locked pytest -v)

# Docker Compose smoke test: build, start, probe, clean up
docker compose up --build --detach --wait
curl --fail-with-body http://127.0.0.1:8000/health/live
curl --fail-with-body http://127.0.0.1:8000/health/ready
docker compose down

# Lint GitHub Actions workflows (needs Docker)
docker run --rm --volume "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -color
```

Each new component adds its own build, lint, and test commands to CI and to
this section in the PR that introduces it.

## Backend

The backend lives in `backend/` (see [architecture.md](architecture.md#backend)).
It needs Python 3.12 and [uv](https://docs.astral.sh/uv/) 0.12.19 (the version
pinned in CI and the Dockerfile). Dependencies are declared in
`backend/pyproject.toml` and locked in `backend/uv.lock`. After changing
dependencies, run `uv lock` and commit the lockfile. CI fails if the lockfile
is out of date.

### Configuration

Copy the example environment file. `.env` is ignored by git; never commit it.

```sh
cp .env.example .env
# Set POSTGRES_PASSWORD in .env, e.g. to the output of: openssl rand -hex 24
```

Docker Compose reads `.env` automatically. The backend itself reads only
`SIGNALHUB_*` environment variables (see
[architecture.md](architecture.md#configuration)). It never reads `.env`
directly.

### Run everything with Docker Compose

```sh
docker compose up --build --detach --wait   # db, then migrate, then api
curl http://127.0.0.1:8000/health/live
curl http://127.0.0.1:8000/health/ready
docker compose logs api
docker compose down                         # keeps the database volume
docker compose down --volumes               # also deletes all data
```

The `migrate` service applies migrations and exits. `api` starts only after
it succeeds, and a failed migration stops startup. Ports are bound to
`127.0.0.1` only. Change them with `SIGNALHUB_PORT` and `POSTGRES_PORT` in
`.env`.

### Run the API on the host

Start only the database in Docker and run the API from source:

```sh
docker compose up --detach --wait db
cd backend
uv sync --locked
set -a; . ../.env; set +a
export SIGNALHUB_DATABASE_URL="postgresql+psycopg://signalhub:${POSTGRES_PASSWORD}@127.0.0.1:${POSTGRES_PORT:-5432}/signalhub"
uv run alembic upgrade head
uv run uvicorn --factory signalhub.main:create_app --reload
```

The interactive API docs are at <http://127.0.0.1:8000/docs>.

### Migrations

Alembic reads `SIGNALHUB_DATABASE_URL`, like the application. Run these from
`backend/`:

```sh
uv run alembic upgrade head                          # apply all migrations
uv run alembic current                               # show the applied revision
uv run alembic revision --autogenerate -m "add x"    # after changing models
uv run alembic check                                 # fail if models and migrations differ
uv run alembic downgrade -1                          # revert the last migration
```

Review every autogenerated migration by hand, and run `ruff format` on it.
Migrations are part of the database contract (see [CLAUDE.md](../CLAUDE.md)).

### Tests

Tests need a PostgreSQL server where the test user may create databases. Each
test creates its own temporary database and drops it afterwards, so existing
data on that server is never touched. The Compose database works:

```sh
docker compose up --detach --wait db
cd backend
set -a; . ../.env; set +a
export SIGNALHUB_TEST_DATABASE_URL="postgresql+psycopg://signalhub:${POSTGRES_PASSWORD}@127.0.0.1:${POSTGRES_PORT:-5432}/signalhub"
uv run pytest -v
```

Without `SIGNALHUB_TEST_DATABASE_URL`, database tests fail instead of being
skipped. The suite covers configuration, startup, health endpoints (including
database outages), transaction handling, and migrations (upgrade, drift check
against the models, and downgrade).

## Repository settings (GitHub)

These settings are required for the model above and live outside the
repository:

- Allow **squash merging** only. Disable merge commits and rebase merging.
- Default squash commit message: **Pull request title** (optionally with
  description). Without this, a single-commit PR uses its commit message
  instead of the validated PR title.
- Protect `main`: require a pull request, and require the status checks
  `Python (lint + test)`, `Backend (test)`, `Docker Compose smoke test`,
  `GitHub Actions lint`, and `Conventional Commit title`.
  Require branches to be up to date before merging.
- Actions workflow permissions must allow `contents: write` for the release
  job (it requests this explicitly).
