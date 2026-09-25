# Database migrations

Flyway applies the SQL files in this directory at startup, in version order,
in every profile. They are the only way the schema changes: Hibernate never
creates or alters tables.

- Name files `V<version>__<description>.sql`, e.g. `V2__add_event_key.sql`.
  Misnamed `.sql` files fail startup instead of being skipped.
- Never edit or delete a migration once it has reached `main`. Add a new one.
- The schema is a public contract. See `docs/architecture.md`.

| Version | Change |
|---|---|
| `V1__create_events.sql` | `events` table for generic producer events |
| `V2__add_producer_authentication.sql` | `producers` and `producer_api_keys` tables; `events.source` replaced by `events.producer_id` |
| `V3__index_events_for_listing.sql` | Indexes on `events` for the event listing |
| `V4__create_clients.sql` | `clients` table: client credentials and push targets |
| `V5__create_push_dispatches.sql` | `push_dispatches` table: events whose push is not yet dispatched |
| `V6__add_event_read_state.sql` | `events.read_at` and an index over unread events |
| `V7__add_client_push_preferences.sql` | Push preferences on `clients`: paused, minimum severity, muted categories and producers |
| `V8__create_push_retries.sql` | `push_retries` table: pushes to one client waiting to be sent again after a temporary failure |
