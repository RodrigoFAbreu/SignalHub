-- Generic events published by producers. The table is part of the public
-- database contract (see docs/architecture.md#events). The backend validates
-- every field before inserting; these constraints are the last line of defence
-- and keep the invariants true for anything that writes to the table.
CREATE TABLE events (
    -- Server-generated UUIDv7: unique across producers and roughly time-ordered.
    id          uuid        PRIMARY KEY,
    source      text        NOT NULL CHECK (char_length(source) BETWEEN 1 AND 100),
    context     text        CHECK (char_length(context) BETWEEN 1 AND 200),
    category    text        NOT NULL
                            CHECK (category IN ('ACTION_REQUIRED', 'BLOCKED', 'COMPLETED', 'INFO')),
    severity    text        NOT NULL CHECK (severity IN ('LOW', 'NORMAL', 'HIGH', 'CRITICAL')),
    title       text        NOT NULL
                            CHECK (char_length(title) <= 200 AND btrim(title) <> ''),
    message     text        CHECK (char_length(message) <= 4000),
    -- Opaque producer metadata. Always a JSON object; empty when not supplied.
    metadata    jsonb       NOT NULL CHECK (jsonb_typeof(metadata) = 'object'),
    -- Producer-supplied time of the underlying occurrence. Context only.
    occurred_at timestamptz,
    -- Canonical time the server accepted the event.
    created_at  timestamptz NOT NULL
);
