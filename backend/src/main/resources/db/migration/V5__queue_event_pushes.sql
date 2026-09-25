-- Events whose push to the owner's clients has not been dispatched yet: a
-- transactional outbox. A row is written in the same transaction as its event
-- and deleted once every client with a push target was sent the push, so a
-- restart between storing an event and pushing it does not lose the push.
-- Events stored before this migration are not queued: they were never meant
-- to trigger a push. See docs/architecture.md#event-triggered-dispatch.

CREATE TABLE pending_pushes (
    event_id   uuid        PRIMARY KEY REFERENCES events (id) ON DELETE CASCADE,
    -- When the event was queued; dispatch takes the oldest first.
    queued_at  timestamptz NOT NULL
);
