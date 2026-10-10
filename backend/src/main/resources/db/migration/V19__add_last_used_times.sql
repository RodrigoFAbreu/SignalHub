-- When a client last made a request and when a producer key last authenticated a publish, so the
-- owner can tell a device or key in use from one forgotten. Written at most about once a minute
-- per client or key, never on every request. Null until first used; existing rows start null.
-- See docs/architecture.md#when-devices-and-keys-were-last-used.
ALTER TABLE clients ADD COLUMN last_active_at timestamptz;
ALTER TABLE producer_api_keys ADD COLUMN last_used_at timestamptz;
