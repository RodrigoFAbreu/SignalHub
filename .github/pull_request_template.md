<!--
PR title = release commit subject on main. It must be a Conventional Commit,
e.g. `feat: add event ingestion` or `fix(api)!: reject unsigned events`.
The "PR title" check shows the release impact. See docs/development.md.
-->

## Purpose

<!-- What does this change do, and why? Link related issues. -->

## Testing

<!-- How was this verified? Tests added or changed, commands run, manual checks. -->

## Release impact

<!-- patch / minor / breaking. What changes for users, producers, or operators of this release? -->

## Compatibility and migration

<!-- Changes to the producer API, event schema, database schema, configuration, or
deployment. Required migration steps, or "None". -->

## Releasable main

- [ ] Merging this PR leaves `main` complete, tested, and releasable on its own.
- [ ] No secrets, credentials, or environment-specific values are committed.
- [ ] Documentation matches the behaviour after this change.
