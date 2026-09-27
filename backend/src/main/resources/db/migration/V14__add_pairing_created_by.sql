-- Pairings created from an admin device: which device created the code, so
-- the pairing notice can name it and the code stops redeeming once that
-- device is revoked or is no longer an admin. See
-- docs/architecture.md#pairing.

-- A nullable column without a default does not rewrite the table. Existing
-- pairings, and every pairing created with the admin token, have none, so no
-- operator action.
ALTER TABLE pairings
    ADD COLUMN created_by uuid REFERENCES clients (id) ON DELETE CASCADE;
