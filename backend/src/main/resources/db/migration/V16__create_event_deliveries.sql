-- An event's delivery records: for each device the dispatcher considered for
-- an event, one row per push attempt, saying how it went. Written by the
-- dispatcher after each send, and for devices it did not send to (their
-- preferences filtered the event out, or they have no push target); never
-- the push token. Kept as long as the event and the device: deleting either,
-- by retention, by the operator or by deleting a revoked device, deletes its
-- rows. See docs/architecture.md#push-dispatch.

-- A new table: existing events simply have no records, so upgrading needs no
-- operator action.
CREATE TABLE event_deliveries (
    id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_id    uuid        NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    client_id   uuid        NOT NULL REFERENCES clients (id) ON DELETE CASCADE,
    -- The first dispatch is attempt 1, each retry one more.
    attempt     integer     NOT NULL CHECK (attempt >= 1),
    outcome     text        NOT NULL
        CHECK (outcome IN ('DELIVERED', 'FILTERED', 'NO_TARGET', 'UNSUPPORTED_PROVIDER',
                           'INVALID_TARGET', 'TRANSIENT_FAILURE', 'PERMANENT_FAILURE')),
    -- Why, when there is more to say: the provider's reason for a failure, or
    -- the preference that filtered the event out. Never a push token.
    detail      text,
    at          timestamptz NOT NULL
);

CREATE INDEX event_deliveries_event_id_idx ON event_deliveries (event_id);
-- So deleting a device does not scan every event's records.
CREATE INDEX event_deliveries_client_id_idx ON event_deliveries (client_id);
