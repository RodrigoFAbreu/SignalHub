-- Pairings: one-time codes that let a new device register itself as a client
-- without the admin token. The operator creates one for a client name; the
-- device redeems it once, before it expires, and gets its own client and key.
-- See docs/architecture.md#pairing.

CREATE TABLE pairings (
    -- Server-generated canonical ID, for logs; never shown to the device.
    id          uuid        PRIMARY KEY,
    -- SHA-256 of the complete pairing code. The code itself is never stored.
    code_hash   bytea       NOT NULL UNIQUE CHECK (octet_length(code_hash) = 32),
    -- The name the client gets when the code is redeemed, as in clients.name.
    client_name text        NOT NULL CHECK (char_length(client_name) BETWEEN 1 AND 100),
    created_at  timestamptz NOT NULL,
    -- After this the code no longer redeems. Redeeming deletes the row, and
    -- expired rows are deleted when the next pairing is created.
    expires_at  timestamptz NOT NULL,
    CHECK (expires_at > created_at)
);
