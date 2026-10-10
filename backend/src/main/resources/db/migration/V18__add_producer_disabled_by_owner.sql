-- Self-service for users: an owner disables and enables their own producers from a device. A
-- producer the operator disabled (or disabled because its owner was revoked) must stay disabled,
-- so the owner cannot undo it: this tells the two apart. Existing disabled producers were disabled
-- by the operator. See docs/architecture.md#own-producers-from-a-device.
ALTER TABLE producers ADD COLUMN disabled_by_owner boolean NOT NULL DEFAULT false;
