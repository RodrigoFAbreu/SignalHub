-- Users, roles and subscriptions: SignalHub serves several people on one server. Every client
-- (device) belongs to one user, every producer is owned by one user, and a user receives only the
-- events of the producers they are subscribed to. A user has a role, BASIC, MOD or ADMIN; a device
-- is an admin device exactly when its user is an ADMIN, so the per-device admin flags go. See
-- docs/architecture.md#users-roles-and-subscriptions.

CREATE TABLE users (
    -- Server-generated canonical ID.
    id         uuid        PRIMARY KEY,
    -- Shown to the operator and, later, to other users choosing whom to allow on a producer.
    -- Unique ignoring case, so two users cannot look alike.
    name       text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100 AND btrim(name) <> ''),
    role       text        NOT NULL CHECK (role IN ('BASIC', 'MOD', 'ADMIN')),
    created_at timestamptz NOT NULL,
    -- Set once the user is revoked: their devices are revoked and their producers disabled.
    -- Revocation is permanent, and a revoked user is never an admin.
    revoked_at timestamptz,
    CHECK (revoked_at IS NULL OR role <> 'ADMIN')
);

CREATE UNIQUE INDEX users_name_lower_idx ON users (lower(name));

-- The existing data becomes the first user's: an ADMIN, so the owner can do exactly what they did
-- before. The name is only a default; the operator renames it on the admin page.
INSERT INTO users (id, name, role, created_at) VALUES (gen_random_uuid(), 'Owner', 'ADMIN', now());

-- Every existing client belongs to the owner. The per-client admin flag goes: the owner is an
-- ADMIN, so every one of their devices is an admin device.
ALTER TABLE clients ADD COLUMN user_id uuid REFERENCES users (id);
UPDATE clients SET user_id = (SELECT id FROM users);
ALTER TABLE clients ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE clients DROP COLUMN admin;
CREATE INDEX clients_user_id_idx ON clients (user_id);

-- A pairing code is always for a given user: the device that redeems it belongs to that user.
-- Codes that are still unredeemed are the owner's.
ALTER TABLE pairings ADD COLUMN user_id uuid REFERENCES users (id);
UPDATE pairings SET user_id = (SELECT id FROM users);
ALTER TABLE pairings ALTER COLUMN user_id SET NOT NULL;
ALTER TABLE pairings DROP COLUMN admin;

-- Every existing producer is the owner's, and private: only its owner sees it. The default makes
-- new producers private too, whatever inserts them.
ALTER TABLE producers ADD COLUMN owner_id uuid REFERENCES users (id);
UPDATE producers SET owner_id = (SELECT id FROM users);
ALTER TABLE producers ALTER COLUMN owner_id SET NOT NULL;
ALTER TABLE producers
    ADD COLUMN visibility text NOT NULL DEFAULT 'PRIVATE' CHECK (visibility IN ('PUBLIC', 'PRIVATE'));
CREATE INDEX producers_owner_id_idx ON producers (owner_id);

-- The users, besides its owner, who see a private producer.
CREATE TABLE producer_allowed_users (
    producer_id uuid NOT NULL REFERENCES producers (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES users (id),
    PRIMARY KEY (producer_id, user_id)
);

CREATE INDEX producer_allowed_users_user_id_idx ON producer_allowed_users (user_id);

-- The producers whose events a user receives. The owner is subscribed to every existing producer.
CREATE TABLE subscriptions (
    user_id     uuid        NOT NULL REFERENCES users (id),
    producer_id uuid        NOT NULL REFERENCES producers (id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL,
    PRIMARY KEY (user_id, producer_id)
);

CREATE INDEX subscriptions_producer_id_idx ON subscriptions (producer_id);

INSERT INTO subscriptions (user_id, producer_id, created_at)
SELECT users.id, producers.id, now() FROM users, producers;

-- Read state per user: the events a user has read, on all of their devices. Deleting an event
-- deletes its rows. events.read_at stays as the operator's own read state, the one the admin token
-- reads and marks, which belongs to no user.
CREATE TABLE event_reads (
    user_id  uuid        NOT NULL REFERENCES users (id),
    event_id uuid        NOT NULL REFERENCES events (id) ON DELETE CASCADE,
    read_at  timestamptz NOT NULL,
    PRIMARY KEY (user_id, event_id)
);

CREATE INDEX event_reads_event_id_idx ON event_reads (event_id);

INSERT INTO event_reads (user_id, event_id, read_at)
SELECT users.id, events.id, events.read_at FROM users, events WHERE events.read_at IS NOT NULL;
