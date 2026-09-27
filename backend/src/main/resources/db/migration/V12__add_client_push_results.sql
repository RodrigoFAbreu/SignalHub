-- Each client's latest push results, for the operator to see why a device
-- got no push: the last push the provider accepted and the last one that
-- failed, each overwritten by the next. Not an attempt history. Written by
-- the dispatcher after each send; never the push token. See
-- docs/architecture.md#push-dispatch.

-- Nullable columns without defaults do not rewrite the table; existing
-- clients have no results yet. Revoking a client keeps them. The event IDs
-- are not foreign keys: the event may have been deleted since (retention),
-- and the result still says what happened.
ALTER TABLE clients
    ADD COLUMN last_push_succeeded_at       timestamptz,
    ADD COLUMN last_push_succeeded_event_id uuid,
    ADD COLUMN last_push_failed_at          timestamptz,
    ADD COLUMN last_push_failed_event_id    uuid,
    -- The delivery result of the failed send.
    ADD COLUMN last_push_failed_result      text
        CHECK (last_push_failed_result IN
            ('UNSUPPORTED_PROVIDER', 'INVALID_TARGET', 'TRANSIENT_FAILURE', 'PERMANENT_FAILURE')),
    ADD CHECK ((last_push_succeeded_at IS NULL) = (last_push_succeeded_event_id IS NULL)),
    ADD CHECK ((last_push_failed_at IS NULL) = (last_push_failed_event_id IS NULL)
           AND (last_push_failed_at IS NULL) = (last_push_failed_result IS NULL));
