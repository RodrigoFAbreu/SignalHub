-- Read state of events: whether the owner has seen an event. There is one
-- owner, so an event is read or unread for all of the owner's clients alike.
-- See docs/architecture.md#read-state.

-- When the owner marked the event read; null while it is unread. Events
-- stored before this migration start unread. Adding a nullable column without
-- a default does not rewrite the table.
ALTER TABLE events ADD COLUMN read_at timestamptz;

-- Unread events in listing order: serves the unread count and marking read
-- every unread event up to a given one, however many events are read.
CREATE INDEX events_unread_created_at_id_idx ON events (created_at, id) WHERE read_at IS NULL;
