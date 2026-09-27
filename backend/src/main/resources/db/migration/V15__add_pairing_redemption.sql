-- Redeemed pairings: redeeming a code now marks its pairing with when and as
-- which client it was redeemed, instead of deleting it, so whoever shows the
-- code can learn that it was used, and by which device. A redeemed pairing
-- never redeems again. Pairings are deleted a while after they expire, used
-- or not. See docs/architecture.md#pairing.

-- Nullable columns without a default do not rewrite the table. Existing
-- pairings are unredeemed, as redeeming used to delete them, so no operator
-- action. Deleting the client deletes the pairing that made it, as for every
-- reference to clients.
ALTER TABLE pairings
    ADD COLUMN redeemed_at timestamptz,
    ADD COLUMN redeemed_by uuid REFERENCES clients (id) ON DELETE CASCADE,
    ADD CHECK ((redeemed_at IS NULL) = (redeemed_by IS NULL));
