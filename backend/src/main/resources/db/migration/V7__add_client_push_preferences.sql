-- Push preferences: which events interrupt the owner on a client. They only
-- decide whether a push is sent; every event is stored and listed whatever
-- they say. Preferences belong to a client, like its push target, so each
-- device can be as quiet as the owner wants. Only generic event fields are
-- used. See docs/architecture.md#push-preferences.

-- Adding NOT NULL columns with constant defaults does not rewrite the table;
-- existing clients keep receiving every push.
ALTER TABLE clients
    -- False pauses every push to the client; its push target is kept.
    ADD COLUMN push_enabled          boolean NOT NULL DEFAULT true,
    -- Events below this severity are not pushed.
    ADD COLUMN push_minimum_severity text    NOT NULL DEFAULT 'LOW'
        CHECK (push_minimum_severity IN ('LOW', 'NORMAL', 'HIGH', 'CRITICAL')),
    -- Events with these categories are not pushed.
    ADD COLUMN push_muted_categories text[]  NOT NULL DEFAULT '{}'
        CHECK (push_muted_categories <@ ARRAY['ACTION_REQUIRED', 'BLOCKED', 'COMPLETED', 'INFO']),
    -- Events of these producers are not pushed. Not foreign keys: an unknown
    -- producer simply matches no events, as in the event listing.
    ADD COLUMN push_muted_producers  uuid[]  NOT NULL DEFAULT '{}'
        CHECK (cardinality(push_muted_producers) <= 100
           AND array_position(push_muted_producers, NULL) IS NULL);
