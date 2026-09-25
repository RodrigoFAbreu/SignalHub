-- Indexes for the event listing (GET /api/v1/events), which orders by
-- (created_at, id) descending and continues after a cursor with a row
-- comparison. See docs/architecture.md#listing-events.

-- The unfiltered inbox, and filters on category, severity or time range.
CREATE INDEX events_created_at_id_idx ON events (created_at, id);

-- The listing filtered by producer. Also serves the producer foreign key.
CREATE INDEX events_producer_id_created_at_id_idx ON events (producer_id, created_at, id);
