-- Answering an event: a producer may ask on an event (a question with choices and/or typed text),
-- the people allowed answer it, and the producer reads the answer or closes the question. See
-- docs/design/answers/API-PROPOSAL.md and docs/architecture.md#answering-an-event.

-- The question, normalized by the API (defaults filled in), as jsonb; null when the event asks
-- nothing, which is every event stored before this migration. ask_closes_at is copied from it so
-- the listing's filters compare a column instead of parsing the document.
ALTER TABLE events ADD COLUMN ask jsonb;
ALTER TABLE events ADD COLUMN ask_closes_at timestamptz;

-- Serves the "to answer" and question-state filters, which look only at events that ask.
CREATE INDEX events_ask_created_at_idx ON events (created_at DESC, id DESC) WHERE ask IS NOT NULL;

-- The users, besides a producer's owner, who may answer its events' questions. Changed under the
-- producer's row lock, like its allow-list.
CREATE TABLE producer_answerers (
    producer_id uuid NOT NULL REFERENCES producers (id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES users (id),
    PRIMARY KEY (producer_id, user_id)
);

CREATE INDEX producer_answerers_user_id_idx ON producer_answerers (user_id);

-- How a question ended: one row per event, so the primary key decides between two answers, and
-- between an answer and the producer's close. Deleted with the event.
CREATE TABLE event_answers (
    event_id    uuid        PRIMARY KEY REFERENCES events (id) ON DELETE CASCADE,
    -- ANSWER, or CLOSE when the producer closed the question (then the person columns are null).
    kind        text        NOT NULL CHECK (kind IN ('ANSWER', 'CLOSE')),
    -- Who answered, and their name as it was then, so a later rename changes nothing.
    user_id     uuid        REFERENCES users (id),
    user_name   text,
    -- APP or WEB: where the answer was given.
    via         text        CHECK (via IN ('APP', 'WEB')),
    -- The ids of the chosen choices, in the ask's order; the typed text.
    choice_ids  text[],
    text        text,
    -- The producer's note on a close.
    note        text,
    answered_at timestamptz NOT NULL,
    -- The answering client, so the notice of the answer can skip its device. No foreign key: a
    -- deleted device does not change a recorded answer.
    client_id   uuid,
    CHECK ((kind = 'ANSWER' AND user_id IS NOT NULL AND user_name IS NOT NULL AND via IS NOT NULL)
        OR (kind = 'CLOSE' AND user_id IS NULL AND choice_ids IS NULL AND text IS NULL))
);
