-- A browser signed in from a device of the user is a client of its own kind: it authenticates with
-- a key held only in an HttpOnly cookie, and its sign-in lasts a fixed time (expires_at). Existing
-- clients are devices and never expire. See docs/architecture.md#signing-in-a-browser.
ALTER TABLE clients
    ADD COLUMN kind text NOT NULL DEFAULT 'DEVICE' CHECK (kind IN ('DEVICE', 'BROWSER')),
    ADD COLUMN expires_at timestamptz;

-- A sign-in a web page has started and a device of a user may approve. Only hashes of the secrets
-- are kept: the secret the page polls with, the short code a person types and the longer code in
-- the QR code. A row is short-lived and is deleted once it has long expired.
CREATE TABLE web_sign_ins (
    id uuid PRIMARY KEY,
    poll_hash bytea NOT NULL,
    code_hash bytea NOT NULL UNIQUE,
    scan_hash bytea NOT NULL UNIQUE,
    browser_name text NOT NULL,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    status text NOT NULL CHECK (status IN ('PENDING', 'ASKED', 'APPROVED', 'CANCELLED', 'SIGNED_IN')),
    -- The device that looked the code up and may approve or cancel it.
    asked_by uuid REFERENCES clients (id) ON DELETE CASCADE,
    -- The user whose browser it becomes, set when a device approves.
    user_id uuid REFERENCES users (id) ON DELETE CASCADE
);

CREATE INDEX web_sign_ins_expires_at ON web_sign_ins (expires_at);
