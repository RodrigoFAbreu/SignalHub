-- Notices of how a question ended (answered, closed or deleted), pushed to the devices that were
-- shown the event so they remove its notification. Each row is sent once to its devices and then
-- deleted: no per-device retry and no delivery record. See docs/architecture.md#answering-an-event.

CREATE TABLE push_notices (
    id              uuid        PRIMARY KEY,
    -- No foreign key: a notice of a deleted event outlives the event.
    event_id        uuid        NOT NULL,
    notice          text        NOT NULL CHECK (notice IN ('answered', 'closed', 'deleted')),
    -- When it may be sent: now, or the question's closesAt.
    due_at          timestamptz NOT NULL,
    -- The device that answered, which needs no notice of its own answer.
    skip_client_id  uuid,
    -- Set only for 'deleted': the devices read before the event went, as its delivery records go
    -- with it.
    client_ids      uuid[],
    -- Set while a sender works on the row; once passed, the row is sent again.
    claimed_until   timestamptz
);

CREATE INDEX push_notices_due_at_idx ON push_notices (due_at);
CREATE INDEX push_notices_event_id_idx ON push_notices (event_id);
