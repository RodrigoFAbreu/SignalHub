-- An event's link: one absolute http or https URL the owner can open from
-- the event. SignalHub stores and returns it as the producer sent it and
-- never fetches it. See docs/architecture.md#events.

-- Null when the producer sent none; events stored before this migration have
-- none. Adding a nullable column without a default does not rewrite the
-- table. The API checks the scheme; the length is bounded here as well.
ALTER TABLE events ADD COLUMN link text
    CHECK (char_length(link) BETWEEN 1 AND 2000);
