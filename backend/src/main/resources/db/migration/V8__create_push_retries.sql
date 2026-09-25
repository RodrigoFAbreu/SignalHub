-- Pushes to retry: one row per event and client whose send failed
-- temporarily (the provider was unavailable, rate-limited or timed out). The
-- dispatcher writes a row in the transaction that completes the event's
-- dispatch, sends again once next_attempt_at has passed, and deletes the row
-- when the push is delivered, fails for good or runs out of attempts. See
-- docs/architecture.md#push-dispatch.

CREATE TABLE push_retries (
    event_id        uuid        NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    client_id       uuid        NOT NULL REFERENCES clients (id) ON DELETE CASCADE,
    -- Sends made so far, the first dispatch included.
    attempts        integer     NOT NULL CHECK (attempts >= 1),
    -- The next send is due from this time on.
    next_attempt_at timestamptz NOT NULL,
    -- Set while a dispatcher works on the row. Once it has passed (the
    -- dispatcher stopped mid-way), the row is claimed and sent again.
    claimed_until   timestamptz,
    PRIMARY KEY (event_id, client_id)
);

CREATE INDEX push_retries_next_attempt_at_idx ON push_retries (next_attempt_at);
