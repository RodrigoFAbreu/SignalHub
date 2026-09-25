-- Registered producers and their API keys. Events become bound to the producer
-- that authenticated when publishing them, replacing the producer-supplied
-- `source`. See docs/architecture.md#producers-and-authentication.

CREATE TABLE producers (
    -- Server-generated canonical ID.
    id          uuid        PRIMARY KEY,
    -- Stable machine-readable name, shown on events. Same rules as the former
    -- events.source, so existing sources migrate unchanged.
    name        text        NOT NULL UNIQUE CHECK (char_length(name) BETWEEN 1 AND 100),
    created_at  timestamptz NOT NULL,
    -- Set while the producer is disabled: none of its keys authenticate.
    disabled_at timestamptz
);

CREATE TABLE producer_api_keys (
    -- The public key ID, embedded in the API key itself so authentication is
    -- a primary-key lookup.
    id          uuid        PRIMARY KEY,
    producer_id uuid        NOT NULL REFERENCES producers (id),
    -- SHA-256 of the complete API key. The key itself is never stored.
    key_hash    bytea       NOT NULL CHECK (octet_length(key_hash) = 32),
    created_at  timestamptz NOT NULL,
    -- Set once the key is revoked. Revocation is permanent.
    revoked_at  timestamptz
);

-- Listing a producer's keys (management API).
CREATE INDEX producer_api_keys_producer_id_idx ON producer_api_keys (producer_id);

-- Existing events were published before authentication existed. Each distinct
-- source becomes a producer without keys, so history keeps its attribution
-- and the owner can issue keys to it later. These attributions were never
-- verified.
ALTER TABLE events ADD COLUMN producer_id uuid REFERENCES producers (id);

INSERT INTO producers (id, name, created_at)
SELECT gen_random_uuid(), source, min(created_at)
FROM events
GROUP BY source;

UPDATE events
SET producer_id = producers.id
FROM producers
WHERE producers.name = events.source;

ALTER TABLE events ALTER COLUMN producer_id SET NOT NULL;
ALTER TABLE events DROP COLUMN source;
