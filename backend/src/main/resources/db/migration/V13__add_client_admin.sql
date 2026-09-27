-- Admin devices: whether a client is one of the owner's admin devices, and
-- whether the device that redeems a pairing becomes one. Only the operator
-- sets it, with the admin token (the admin page or the management API). See
-- docs/architecture.md#admin-devices.

-- A constant default adds the columns without rewriting the tables; existing
-- clients and unredeemed pairings are not admins, so no operator action.
ALTER TABLE clients ADD COLUMN admin boolean NOT NULL DEFAULT false;
ALTER TABLE pairings ADD COLUMN admin boolean NOT NULL DEFAULT false;
