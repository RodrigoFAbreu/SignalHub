-- Registered clients: the owner's installations of SignalHub client apps (a
-- phone, a desktop app, a CLI). Each has its own credential for reading events
-- and at most one push target for future delivery. The push target is opaque:
-- SignalHub stores a provider name and a provider-issued token, and never
-- interprets the token. See docs/architecture.md#clients.

CREATE TABLE clients (
    -- Server-generated canonical ID, also embedded in the client key.
    id                   uuid        PRIMARY KEY,
    -- Human-readable label chosen by the owner, e.g. "Pixel 8". Not unique.
    name                 text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
    -- SHA-256 of the complete client key. The key itself is never stored.
    key_hash             bytea       NOT NULL CHECK (octet_length(key_hash) = 32),
    created_at           timestamptz NOT NULL,
    -- Set once the client is revoked. Revocation is permanent.
    revoked_at           timestamptz,
    -- Where pushes for this client go: a push provider name and the address
    -- that provider issued to the installation. All three are set together.
    push_provider        text        CHECK (char_length(push_provider) BETWEEN 1 AND 50),
    push_token           text        CHECK (char_length(push_token) BETWEEN 1 AND 4096),
    push_updated_at      timestamptz,
    CHECK ((push_provider IS NULL) = (push_token IS NULL)
       AND (push_provider IS NULL) = (push_updated_at IS NULL)),
    -- A revoked client never receives pushes.
    CHECK (revoked_at IS NULL OR push_provider IS NULL)
);
