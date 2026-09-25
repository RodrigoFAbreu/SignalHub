You are bootstrapping a new greenfield project named SignalHub.

SignalHub is a producer-agnostic personal notification platform. Arbitrary systems such as autonomous agents, CI systems, monitoring tools, homelab services, scripts, or future applications will be able to publish generic events, which SignalHub can persist and eventually deliver to a mobile application.

This task is ONLY the project and engineering bootstrap. Do not attempt to implement the complete product.

## Development model

This repository uses lightweight trunk-based development.

`main` is always releasable.

Every commit that reaches `main` represents a release.

Development must therefore follow these rules:

- Never work directly on `main`.
- Use short-lived branches.
- Changes reach `main` through pull requests.
- Pull requests are squash merged.
- One merged pull request becomes one commit on `main`.
- Every merge to `main` must leave the entire repository in a valid, tested, releasable state.
- Do not merge partial or knowingly broken scaffolding.
- CI must validate all relevant components before merge.
- Prefer vertically complete increments over incomplete structural commits.
- Do not commit secrets or environment-specific credentials.

Use Conventional Commit semantics for pull request/release commit titles.

Examples:

- `feat: bootstrap backend`
- `fix: prevent duplicate event delivery`
- `docs: document producer API`
- `refactor: simplify event persistence`

The project will initially use pre-1.0 semantic versioning.

## Product architecture direction

The intended system is:

- Android application: Kotlin + Jetpack Compose
- Backend: Python + FastAPI
- Persistence: PostgreSQL
- Push delivery: Firebase Cloud Messaging
- Producer client: Python SDK/CLI
- Deployment: Docker / Docker Compose

Do not implement all of these in this bootstrap task.

The architecture must remain producer-agnostic. Core SignalHub code must not contain special-case behavior for Workflow Controller, Claude, GitHub, or any other individual producer.

## Bootstrap task

Establish a high-quality repository baseline suitable for autonomous future development.

Create:

1. `CLAUDE.md`
   - project principles
   - repository development rules
   - trunk-based/release semantics
   - engineering standards
   - testing expectations
   - prohibition on secrets
   - producer-agnostic architecture rule

2. `README.md`
   - concise project purpose
   - high-level intended architecture
   - current development status
   - basic development philosophy

3. `docs/architecture.md`
   - initial system boundaries
   - producer → backend → push/mobile flow
   - distinction between generic event semantics and producer-specific metadata
   - likely components without prematurely specifying implementation details

4. `docs/development.md`
   - branching model
   - PR expectations
   - Conventional Commit PR titles
   - release semantics
   - definition of releasable main

5. GitHub Actions CI baseline appropriate for the repository's current contents.
   The CI itself must be useful and green, not placeholder theater.

6. A PR template covering:
   - purpose
   - testing
   - release impact
   - compatibility/migration concerns
   - confirmation that the resulting main revision is releasable

7. Sensible `.gitignore`, editor/configuration files, and other lightweight repository hygiene where justified.

## Release model

Design and document an automated release strategy where every successful merge to `main` results in a semantic version tag and GitHub release.

Do not introduce a release mechanism that requires a later release PR, because every main commit itself is already considered a release.

The mechanism should eventually support:

- `feat` → minor
- `fix` → patch
- `feat!` / breaking change → major
- other normal non-breaking commit types → patch

Since the project is pre-1.0, document any deliberate interpretation of breaking/minor changes clearly.

If fully implementing the automatic release workflow during this bootstrap is safe and testable, do so. Otherwise establish the design and implement only what can be proven correct without introducing an unreliable release mechanism.

## Execution expectations

First inspect the repository.

Then:

1. formulate the minimal coherent bootstrap
2. implement it
3. run all applicable validation
4. review your own changes for unnecessary complexity
5. ensure documentation matches actual repository behavior
6. leave the branch ready for a pull request

Do not merge to `main`.

Do not expand into backend or Android feature implementation during this task.

When finished, report:
- what was created
- what validation was run
- any decisions that need human review
- whether the branch is genuinely safe to merge as the initial releasable baseline
