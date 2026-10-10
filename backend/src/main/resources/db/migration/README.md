# Database migrations

Flyway applies the SQL files in this directory at startup, in version order,
in every profile. They are the only way the schema changes: Hibernate never
creates or alters tables.

- Name files `V<version>__<description>.sql`, e.g. `V2__add_event_key.sql`.
  Misnamed `.sql` files fail startup instead of being skipped.
- Never edit or delete a migration once it has reached `main`. Add a new one.
- A release refuses to start on a database holding a migration it does not
  have, so going back to an older release means restoring a backup.
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
| `V9__add_event_idempotency_key.sql` | `events.idempotency_key`, unique per producer: publishing again with the same key returns the stored event |
| `V10__create_pairings.sql` | `pairings` table: hashes of one-time pairing codes that register a new client |
| `V11__add_event_link.sql` | `events.link`: an optional URL the owner can open from the event |
| `V12__add_client_push_results.sql` | Each client's last successful and last failed push on `clients`, for the management API |
| `V13__add_client_admin.sql` | `clients.admin` and `pairings.admin`: whether a client is an admin device, and whether a pairing makes one |
| `V14__add_pairing_created_by.sql` | `pairings.created_by`: the admin device that created a pairing, if one did |
| `V15__add_pairing_redemption.sql` | `pairings.redeemed_at` and `pairings.redeemed_by`: when a pairing was redeemed, and as which client |
| `V16__create_event_deliveries.sql` | `event_deliveries` table: how each push of an event to each device went, for the operator; deleted with the event or the device |
| `V17__create_users_roles_subscriptions.sql` | `users` table with roles; every client, pairing and producer belongs to a user (`clients.admin` and `pairings.admin` replaced by the user's role); producer visibility and allow-list; `subscriptions`; per-user read state in `event_reads`. The existing data becomes the first user's |
