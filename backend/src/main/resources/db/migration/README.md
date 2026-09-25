# Database migrations

Flyway applies the SQL files in this directory at startup, in version order,
in every profile. They are the only way the schema changes: Hibernate never
creates or alters tables.

- Name files `V<version>__<description>.sql`, e.g. `V1__create_events.sql`.
  Misnamed `.sql` files fail startup instead of being skipped.
- Never edit or delete a migration once it has reached `main`. Add a new one.
- The schema is a public contract. See `docs/architecture.md`.

No migrations exist yet: SignalHub has no tables until the first feature that
stores data adds them.
