-- Events whose push has not been dispatched yet: an outbox. A row is written
-- in the same transaction as its event, so an acknowledged event is never
-- left without a push, even if the backend stops before sending it. The
-- dispatcher claims a row, pushes to every client with a push target, then
-- deletes the row. See docs/architecture.md#push-dispatch.

CREATE TABLE push_dispatches (
    event_id      uuid        PRIMARY KEY REFERENCES events (id) ON DELETE CASCADE,
    -- The event's created_at: rows are dispatched oldest first.
    created_at    timestamptz NOT NULL,
    -- Set while a dispatcher works on the row. Once it has passed (the
    -- dispatcher stopped mid-way), the row is claimed and dispatched again.
    claimed_until timestamptz
);
