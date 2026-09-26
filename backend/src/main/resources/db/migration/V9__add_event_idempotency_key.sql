-- Idempotent publishing: a producer may send an optional key with an event,
-- and sending the same key again returns the stored event instead of storing
-- a second one. Keys are scoped to their producer. See
-- docs/architecture.md#idempotent-publishing.

-- The key the producer sent in the Idempotency-Key header; null when it sent
-- none. Events stored before this migration have none. Adding a nullable
-- column without a default does not rewrite the table.
ALTER TABLE events ADD COLUMN idempotency_key text
    CHECK (idempotency_key ~ '^[!-~]{1,200}$');

-- One event per producer and key. Partial, so events without a key cost
-- nothing in it. Deleting an event (retention) frees its key.
CREATE UNIQUE INDEX events_producer_idempotency_key_idx
    ON events (producer_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
