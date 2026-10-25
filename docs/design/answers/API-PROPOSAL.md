# Answering an event: the API proposal (R81)

Status: approved at G8 (2026-10-25), with the changes in section 10. Built on the owner's decisions of
2026-10-16 and on an inventory of today's event detail, inbox, notification code and event API. Words: a producer **asks**, a
person **answers**; the API says `ask` and `answer`. Nothing here names a producer: an ask is
generic choices and text, and SignalHub never interprets them (principle 1).

## 1. Asking: a new optional field on `POST /api/v1/events`

```json
{
  "category": "ACTION_REQUIRED", "severity": "HIGH",
  "title": "Merge R82 into main?", "message": "CI passed. 3 files changed.",
  "ask": {
    "choices": [{"id": "merge", "label": "Merge", "description": "Squash-merge now; CI passed."},
                {"id": "hold", "label": "Hold"}],
    "multiple": false,
    "text": "OPTIONAL",
    "closesAt": "2026-10-17T09:00:00Z"
  }
}
```

| Field | Rule |
|---|---|
| `choices` | 0 to 10 items. `id`: `Identifiers.PATTERN`, at most 64, unique in the ask. `label`: 1 to 100 characters, no control characters (line breaks included), unique ignoring case (`Locale.ROOT`). `description`: optional, at most 1000 characters, no NUL; shown under the label in the app and on the web page, and nothing at all when absent or empty (the owner, 2026-10-16). Never in the notification's hint line. |
| `multiple` | `false` by default. `true` = pick one or more; needs at least 2 choices; the *Other* row doesn't count. |
| `text` | `NONE`, `OPTIONAL` or `REQUIRED`. When omitted: `NONE` with choices, `REQUIRED` without. Without choices, it must be `REQUIRED` (a typed question). Typed answers are 1 to 3000 characters. |
| `textStyle` | Only with choices and `text` not `NONE`: `NOTE` (the default) or `OTHER`. `NOTE`: the typed text is a note written alongside the chosen choice. `OTHER`: an *Other* row is picked instead of a choice, and the typed text is the answer (as in Claude Code's prompt); with `multiple`, the *Other* row can be ticked with the choices. Chosen by the producer per question (the maintainer, G8). Sent with no choices, or with `text: NONE`, it is a `400` on `ask.textStyle`. |
| `closesAt` | Optional, with an offset, in the future, at most 30 days ahead. After it nobody can answer. |

- An event without `ask` behaves exactly as today. `ask` is stored with the event (a nullable
  `jsonb` column, V21, like V11's `link`). It is stored normalized: defaults filled in, `closesAt`
  as a UTC instant truncated to microseconds, `ask: null` the same as absent. The normalized ask
  joins the idempotency comparison (`EventService.sameRequest`).
- The checks that `closesAt` is in the future and at most 30 days ahead run in the service, after
  the `Idempotency-Key` lookup. A retry of a published question then returns the stored event
  (`200`, with its current state), even after `closesAt` has passed.
- `whoCanAnswer` is response-only: sending it is a `400` (strict JSON).
- V21 also adds `ask_closes_at timestamptz` (nullable), copied from the ask, so the list filters
  compare it without parsing the jsonb.
- The operator's test event (`POST /api/v1/admin/producers/{id}/events`) accepts `ask` too, so the
  feature can be tried from the admin page.
- `ask` is returned in every event response.

## 2. Who may answer

- The producer's **owner**, and the users the owner names as **answerers** of that producer.
  Answerers must be users who can see the producer (owner, public, or on the allow-list).
- To answer an event, a person must also be able to read it today (subscribed to the producer).
  The app says so where it matters: "Stay subscribed to answer".
- **First answer wins**: the first accepted answer ends the question for everyone.
- Everyone else the event reached sees the question read-only, with who answered and what.
- The operator (admin token) acts for no user, so it **never answers**. The admin page shows the
  question and the answer read-only.
- Answerers are a new table `producer_answerers (producer_id, user_id)` beside
  `producer_allowed_users`, under the same producer row lock.
- Managed by the owner under `/api/v1/client/producers/{id}`:
  - `PUT|DELETE /answerers/{userId}`;
  - `OwnProducerResponse` gains `answerers [{id, name}]`.
  - The admin API shows them read-only in the producer response: they are the owner's choice.
- `PUT /answerers/{userId}`: `200` with `OwnProducerResponse`. The owner, or someone already on
  the list, changes nothing. A user who is unknown or revoked: `404`. A user who can't see the
  producer: `409`.
- `DELETE`: `200`; someone not on the list changes nothing.
- A user leaves the list, in the same transaction, when:
  - `UserService.revoke` revokes them;
  - they are removed from the allow-list, by the owner or by the operator's `allowedUserIds`;
  - a producer they don't otherwise see is made private, by the owner or by the operator.
- The admin API accepts no answerers field.

## 3. Answering: `PUT /api/v1/events/{id}/answer`

Client key or browser cookie (with CSRF), never the admin token (`403`). Body:
`{"choices": ["merge"], "text": "after lunch"}`.

| Answer | When |
|---|---|
| `200` + the event's `answer` | Accepted. The same person sending the same answer again also gets `200` (a doubled tap is harmless). |
| `400` | Unknown choice; no choice where one is needed; several for a single choice; text missing, too long, or not allowed. |
| `403` | This person may not answer this producer's questions. |
| `404` | Not in this person's inbox (not subscribed, deleted, or no such event). |
| `409` + the state | Already answered (by someone else, or differently by the same person), or closed (`closesAt` passed, or the producer closed it). The body carries the state (section 4), so the page shows who answered and what, or who closed it. |

- `409` bodies are an `ApiError` with one more field, `question`: the state of section 4. It is
  absent from every other error. An event that asks nothing gives a plain `ApiError` `409`.
  `ApiError` gains a nullable, `NON_NULL` `question`. This is additive.

The body is checked against the ask:
- `choices` absent and `[]` are the same. `text` absent and `null` are the same.
- Any text given is not blank, has no NUL, and is 1 to 3000 characters.
- Unknown or repeated ids are `400`. Choices are stored in the ask's order.
- "The same answer" (the `200` above) is the same set of choice ids and an equal text.

| Ask | Valid answer |
|---|---|
| no choices (`REQUIRED`) | no choices, text |
| `NONE`, single / multiple | exactly 1 / at least 1 choice, no text |
| `OPTIONAL` `NOTE`, single / multiple | exactly 1 / at least 1 choice, text optional |
| `REQUIRED` `NOTE`, single / multiple | exactly 1 / at least 1 choice, and text |
| `OPTIONAL` `OTHER`, single | either 1 choice and no text, or no choice and text (*Other*) |
| `OPTIONAL` `OTHER`, multiple | at least 1 choice, or text, or both (text means *Other* is ticked) |

Stored in `event_answers`:
- `event_id`: the primary key, with an FK `ON DELETE CASCADE`. The primary key makes first-answer-wins
  atomic (`INSERT ... ON CONFLICT DO NOTHING`).
- `kind`: `ANSWER` or `CLOSE`. A producer's close is a row of `kind = CLOSE`, with `user_id`,
  `user_name`, `via`, `choice_ids` and `text` null, and `note` set. The primary key on `event_id`
  therefore decides between an answer and a close, as it decides between two answers.
- `user_id` and `user_name`: the name is kept as it was, so a later rename doesn't change the record.
- `choice_ids text[]`, `text`, `answered_at`.
- `via`: `APP` or `WEB`, for the admin page's record.
- `client_id`: the answering client, for the notice that skips it (section 6). Null for a close.

The races, as the store handles them:
- The answer and the close are one `INSERT … SELECT … WHERE ask_closes_at IS NULL OR ask_closes_at
  > :now ON CONFLICT (event_id) DO NOTHING`, with one clock: the server's.
- When nothing is inserted, the row is re-read to tell `ANSWERED` from `CLOSED`.
- An FK violation, because the event was deleted meanwhile, is `404`.

## 4. Reading the answer as the producer: `GET /api/v1/events/{id}/answer?wait=60`

Producer key. Only the producer's own events (`404` otherwise, also once the event is deleted). Any
of the producer's keys may read it.

```json
{"state": "ANSWERED", "answer": {"choices": ["merge"], "text": null,
  "by": {"id": "…", "name": "Rodrigo"}, "via": "APP", "at": "2026-10-16T19:02:11Z"},
 "closedBy": null, "closedAt": null, "closeNote": null}
```

- `state`: `OPEN`, `ANSWERED` or `CLOSED`. `answer` is `null` unless `ANSWERED`.
- `closedBy` (`PRODUCER` or `TIME`), `closedAt` and `closeNote` are `null` unless `CLOSED`.
  `closedAt` is `closesAt` for `TIME`, and the close's time for `PRODUCER`. `closeNote` is the
  producer's note, or `null`.
- This object is "the state" wherever this proposal says so (sections 3, 4b, 7).
- `wait`: 0 (the default) to 60 seconds. It holds the request until the state leaves `OPEN` or the
  wait ends, then returns the current state. A producer that wants to wait longer asks again.
- An event without an ask: `409`.
- Implementation notes for R82:
  - `wait` is a whole number from 0 to 60; anything else is `400`.
  - The request registers with an in-process notifier for the event *before* it reads the state, so
    no change is missed.
  - It holds no transaction or connection while it waits (it waits on a virtual thread,
    `@RunOnVirtualThread`, Java 25).
  - It wakes when:
    - an answer or a close commits for the event (notified after commit);
    - `closesAt` arrives;
    - any event deletion commits (every held wait re-reads, so deletion by any path, retention
      included, ends the wait with `404`);
    - `wait` ends.
  - On shutdown, held waits return the current state.
  - At most 200 waits at once; beyond that, it answers at once with the current state.
  - The proxy sets no response timeout and the backend sets none (found when the proxy and backend were checked), so 60 s
    passes through Caddy.
- No callback URL, and no feed of all answers for now. A later item adds them if a producer needs
  them.

## 4b. Closing a question as the producer: `POST /api/v1/events/{id}/answer/close`

Producer key, the producer's own events only. Body: optional `{"note": "Answered in the session"}`.
For a question answered somewhere else, for example in a session the event links to
(the maintainer, G8).

| Answer | When |
|---|---|
| `200` + the state | Closed now, or already closed by the producer (repeating is harmless). |
| `200` + the state | Already closed by `closesAt`: the state says `closedBy: TIME`. |
| `409` + the state | Someone answered first, so the producer learns that answer. |
| `409` | An event without an ask. |
| `404` | Not its event, deleted, or no such event. |

- The state becomes `CLOSED` with `closedBy: PRODUCER` (`closedBy: TIME` when `closesAt` passed),
  `closedAt` and the note in `closeNote` (section 4). Pages say *Closed by ci-pipeline · Answered
  in the session* (or without the note).
- `note`: not blank, no NUL, 1 to 200 characters. With no body, the request closes the question
  without a note.
- Closing again keeps the first close's note and time. A different note is ignored.
- The `closed` notice goes at once, to every device the question reached, and removes the
  question's notifications, as for any closed question (section 6).
- A held wait returns `CLOSED` at once.

## 5. What clients see on an event

`EventResponse` gains:
- `ask` (or `null`);
- `answer` (or `null`), as in section 4;
- `answerState`: `OPEN`, `ANSWERED`, `CLOSED`, or `null` without an ask;
- `closedBy`, `closedAt` and `closeNote`, as in section 4 (or `null`);
- `canAnswer`: whether this caller may answer now. Always `false` for the admin token and producers.

`answerState` and `state` are derived: `CLOSED` as soon as `closesAt` passes, whether or not the
closing notice has been sent yet, so a `409` and a list filter never disagree. The admin list's
`answerState` filter and `toAnswer` use the same derived state.

`GET /api/v1/events` gains a filter, `toAnswer=true`: open questions this caller may answer. This is
the app's and web page's *To answer* chip, and the source of a count next to the unread count.
- `GET /api/v1/events/unread-count` gains `toAnswer`, the open questions this caller may answer.
  It is always 0 for the admin token.
- `toAnswer` takes only `true` (any other value is `400`). With the admin token, the list is
  always empty (G1, settled 6).
- Opening an event still marks it read.
- "Mark all as read" marks questions read like any event. They stay in *To answer*.
- An open question stays in *To answer* until it's answered or closed, whatever its read state.
- `DeletedEvents` gains `asking`: how many of the counted events ask, with `dryRun` too.

### Settled while drawing (step 4a)

- **An answer stores choice ids.** Pages show labels by looking them up in the event's `ask`. The
  admin page shows labels too. Descriptions are never part of an answer.
- **Read state and the question are separate.** The unread dot is read state only. "To answer" is
  shown by its own line on the row, so opening a question marks it read while it stays in *To answer*.
- **The *To answer* chip appears only while its count is above 0, or while it is switched on.** A
  person who never gets questions never sees it.
- **The answerers picker can't know who is subscribed**: the owner doesn't see subscriptions. So it
  says "They also need to be subscribed to get its questions".
- **"Stay subscribed to answer" lives on the producer's page.** An unsubscribed owner can't open the
  event at all.

### Settled while drawing (step 4c)

- **Who can answer, by name:** `ask` in every event response carries `whoCanAnswer [{id, name}]`,
  the owner first, then the answerers. Pages say "Rodrigo answers this" or "Rodrigo or Ana can
  answer". Any device can already list users' names, so this reveals nothing new. `whoCanAnswer`
  leaves out revoked users. When the owner is revoked, it lists only the answerers, and it may be
  empty (an open question nobody can answer until `closesAt`).
- **The chip rule is the one above** (shown only while its count is above 0 or it is on). The app's
  frame 3c follows it in the fix round.
- **An open card goes stale if nothing refreshes it.** The web page re-reads an open event when its
  tab regains focus, and after any `409`. The app does the same on resume, as it already does for
  the inbox. A first load always shows the current state.
- **A `403` on answering** may be a CSRF refusal or "not allowed". The page re-reads the event:
  - if `canAnswer` is now `false`, it shows the read-only card;
  - otherwise it shows "Answer not sent" with Retry.

### Settled while drawing (step 4d)

- **The `answer` object carries `via`** (`APP` or `WEB`) next to `by {id, name}`, with the name as it
  was when the answer was given. The admin page shows "Answered in the app" or "Answered on the web
  page".
- **Choice ids are always sent by the producer.** The server never derives them. The SDK, the
  command and the admin dialog derive an id when it is left out, all by the same rule:
  - lower-case, accents removed; every run of characters other than `a`–`z` and `0`–`9` becomes `-`;
    trimmed of `-`; cut to 64 characters, leaving room for a suffix, and trimmed again;
  - `choice-N` (its position) when nothing is left;
  - `-2`, `-3` and so on added on a collision.
- **The admin test event** uses the same validation as producers. Errors name the field (`ask.closesAt`
  and so on), so the dialog shows them on the field.
- **"Rodrigo or Ana can answer"** on the admin page may name someone who has since unsubscribed.
  Accepted: the operator doesn't see subscriptions there either.

### Settled at the reviews (step 5)

- **A chip row on the inbox**, app and web: *Unread* and *To answer*. *Unread* is the same switch as
  today's unread-only option in the filter sheet, and the sheet keeps it. It's a design addition
  with no API change, approved at G8.

## 6. Pushes

Decided by the owner on 2026-10-16: **no action buttons**. Every question is answered by opening the
event, and notifications stay notification messages, built by Android from FCM as today. So the
critical alert, `PushAlertReceiver` and the channel stay as they are.

- **Tag:** every event push gains `android.notification.tag = eventId`, so a later push with the same
  tag replaces it in place.
- **The provider boundary:**
  - `PushMessage` gains a neutral `tag` (the event ID) and a data-only form, with no title or body.
    `FcmPushProvider` maps `tag` to `android.notification.tag`, and a data-only message to a
    message with no `notification` block, at NORMAL priority.
  - Every event push carries the tag, so a retried push replaces its card instead of adding a
    second one.
- **The "Tap to answer" line:** for a question this device's user may answer, the server adds a last
  line to the push body. The server knows who may answer, and the line is built from the ask alone:
  - "Tap to answer · Merge or Hold" for at most 3 single choices;
  - "Tap to answer · 7 choices", or "Tap to answer · pick one or more";
  - "Tap to answer" for a typed question.
  - Up to 3 choices are listed by label, joined as "Merge or Hold", or "Restart, Wait or Ignore".
    When the whole line would pass 80 characters, it says "Tap to answer · 3 choices" instead.
  - The line follows the shortened message after a line break. With no message, the body is the
    line alone.
  - `multiple` gives "pick one or more" whatever the count.
  - The *Other* row is never named or counted.
  - The 80 characters count the whole line.
  - The worst case (a 200-character title, 500 code points of message, an 80-character line, the
    data and the tag) stays under FCM's 4 KiB.

  Tapping opens the event, as today.
- **Per recipient:** the push text is already built per device; the "Tap to answer" line goes only
  to devices whose user may answer. Everyone else gets the event's usual text.
- **When answered, closed or deleted:** SignalHub sends a **data-only** push with `notice=answered`
  (or `closed`, `deleted`) and the `eventId`.

  | Transition | Notice | Devices | When |
  |---|---|---|---|
  | Answered | `answered` | those with a `DELIVERED` record for the event, except the answering client | at once |
  | Closed by the producer | `closed` | those with a `DELIVERED` record | at once |
  | Closed by `closesAt` | `closed` | those with a `DELIVERED` record | at `closesAt`, only if it was not answered or closed before |
  | Deleted while `OPEN` | `deleted` | read **before** the delete, in its transaction | after the delete |
  | Deleted once answered or closed, repeated close, same answer again | none | | |

  - Recipients include devices whose user has since lost access or unsubscribed: the notice
    removes a card they already have.
  - A notice is not sent while the event's own `push_dispatches` row still exists. It waits, so the
    first dispatch can't add recipients after the notice. Once the question is not `OPEN`, the
    dispatcher and its retries don't send the event push to a device; the skip is recorded as
    `FILTERED` with the detail `question answered` or `question closed`.
  - Notices live in a new table, `push_notices`: `id`, `event_id` without an FK (a `deleted` notice
    outlives the event), `notice`, `due_at`, `skip_client_id`, `client_ids uuid[]` (set only for
    `deleted`) and `claimed_until`. Every delete path writes it: one, a selection, a producer's,
    older than, and retention. Each row is sent once to its devices and then deleted, with no
    per-device retry and no `event_deliveries` record.
  - The app's native `PushAlertReceiver` already receives every FCM message, even when the app isn't
    running. It removes the notification tagged with that `eventId` and plays nothing.
  - Chosen by the owner (2026-10-16) over replacing the notification in place. The notification drawing found that a replacement pops up
    again as a heads-up, brings back a card the person swiped away, and sounds SignalHub's alert
    again (a server-built notification can't say "alert once").
  - The outcome shows in the app's inbox and event screen instead.
  - **Closing** is a dispatch scheduled for `closesAt`: an outbox row due then. It sends `closed` only
    if the question is still open.
  - A device that is offline or dozing keeps the question until the push arrives; a tap then opens
    the event and shows its current state.
- **Effect on the roadmap:** R83 (notification action buttons) is dropped (section 10). The
  notification work above is split between R82a (tag, line, notices) and R82b (the app's receiver).

## 7. Python SDK and the `signalhub` command

- `publish(..., ask=Ask(choices=[Choice("merge", "Merge", description="Squash-merge now"), Choice("hold", "Hold")], multiple=False,
  text="OPTIONAL", text_style="NOTE", closes_at=...))`.
- `close_question(event_id, note=None)`: section 4b; returns the state, or raises with the answer
  when someone answered first.
- `wait_answer(event_id, timeout=None)`: repeats 60 s waits until answered, closed, or `timeout`
  passes. Its socket timeout is the wait plus 15 s.
  - When a wait returns `OPEN` well before its `wait` (in under 5 s), `wait_answer` sleeps 5 s
    before asking again.
  - Temporary errors (connection errors, `502`/`503`, the backend restarting during an upgrade)
    are retried after 5 s until `timeout`.
  - A `404` raises at once.
  - `timeout=None` means no limit.
- `signalhub send ... --choice merge=Merge --choice-description merge='Squash-merge now' --choice hold=Hold [--multiple] [--text optional|required] [--text-style note|other]
  [--closes-in 2h]` prints the event ID as today.
- `signalhub wait-answer EVENT_ID [--timeout 30m] [--json]`:
  - It prints the chosen choice ids, one per line, then, when there is text, an empty line and the
    text (ids are never empty, so the empty line separates them). `--json` prints the state; the
    closed state carries `closedBy`, `closedAt` and `closeNote`.
  - It exits 0 when answered, 5 when closed (by time or by the producer), 6 when its own
    `--timeout` passed (no default, meaning no limit), and 1 when the event is gone or isn't the
    producer's, so a shell script can branch on it.
  - `--timeout` and `--closes-in` take `s`, `m`, `h` or `d`.
  - The SDK sends `multiple`, `text` and `text_style` only when given.
- `signalhub close-question EVENT_ID [--note TEXT]`: exits 0 when closed, also when it was already
  closed by its time, and 7 when someone answered first (and prints that answer).
- An example in `examples/` asks a question and waits, using only the public API.

## 8. Edge cases, settled

| Case | Behaviour |
|---|---|
| Event deleted (by the operator or retention) while open | The answer goes with it (cascade). Reading gives `404`, a held wait returns `404`, and the app shows "isn't in your inbox any more". |
| Producer disabled | People can still answer; the producer reads the answer once it's enabled again (its keys don't work while disabled). |
| Answerer revoked or loses sight | Leaves the answerers list at once. An answer they already gave stays, with their name as it was. |
| Owner unsubscribed | Can't answer until they subscribe again (they can't read the event). The producer's page says "Stay subscribed to answer". |
| Two answers at once | The primary key decides. The loser gets `409` with the winner's answer, and the page shows it ("Ana answered first: Hold"). |
| Answer after `closesAt` | `409` closed. The page shows "Closed · nobody answered in time". |
| Answered elsewhere, e.g. in a linked session | The producer closes its question (section 4b). If someone answered in SignalHub first, the close is refused with that answer. |
| Answer after the producer closed | `409` with the state. The page shows *Closed by NAME* (and the note). |
| Producer closes after `closesAt` | `200` with the state (`closedBy: TIME`); the command exits 0. |
| Producer closes a deleted event | `404`. |
| Test event from the operator | Asks like any other, and is the producer's own event: the owner and answerers answer it, and any of the producer's keys reads or closes it. The operator reads the state on the admin page (`GET /api/v1/events/{id}`). |

## 8b. The states and every endpoint's answer

States: `OPEN` → `ANSWERED` (an answer is accepted) or `CLOSED` (`closedBy: PRODUCER`, by the
close; `closedBy: TIME`, once now ≥ `closesAt`). `ANSWERED` and `CLOSED` are final. Deleting the
event ends any state. `CLOSED`/`TIME` is derived when read, never written; the row due at
`closesAt` only sends the notice.

| | OPEN | ANSWERED | CLOSED (TIME) | CLOSED (PRODUCER) | deleted | no ask |
|---|---|---|---|---|---|---|
| `PUT …/answer` | `200`, `400`, `403` | `200` (same person, same answer), else `409` | `409` | `409` | `404` | `409` |
| `GET …/answer` | `200` (held up to `wait`) | `200` | `200` | `200` | `404` | `409` |
| `POST …/answer/close` | `200` | `409` | `200` | `200` | `404` | `409` |
| `GET /events/{id}` | `canAnswer` per caller | `canAnswer: false` | `false` | `false` | `404` | `answerState: null` |

`PUT …/answer` checks in this order:
1. the admin token is `403`, and a producer key is `401`;
2. not in the caller's inbox is `404`;
3. may not answer is `403`;
4. the body against the ask is `400`;
5. not `OPEN` is `409`, unless the stored answer is the caller's user's and equal to this one,
   which is `200`.

## 9. Compatibility and splitting

- Everything is additive (`feat`, minor): a new optional field, new endpoints, new response fields.
  Old apps ignore `ask` and show the event as today.
- Decided at G8: **R82a** (server, SDK and command, with an example; the tag, the "Tap to answer"
  line, the removal notices, the producer's close) and **R82b** (answering in the app, on the web
  page and on the admin page, the answerers setting, the receiver removing a question's
  notification, and the admin events list's *Question* filter). R83 is dropped.

## 10. Decided at G8 (2026-10-25)

The maintainer approved this proposal and the designs, with these changes:

- Sizes: choice labels up to 100 characters, descriptions up to 1000, typed answers up to 3000
  (section 1). Up to 10 choices and `closesAt` at most 30 days ahead stay; the event's title stays
  at 200 characters.
- `textStyle` (section 1): the producer chooses a note alongside the choice or an *Other* row.
- The producer closes a question answered elsewhere (section 4b).
- An answer is final once sent. The notification line's limit stays 80 characters.
- On the web page, Ctrl+Enter (Cmd+Enter on a Mac) sends the answer; Enter alone never does.
- The admin events list gets an `answerState` filter (`OPEN`, `ANSWERED`, `CLOSED`, `NONE`; admin
  token only, like `userId`; repeatable, like `category`) in R82a, and its *Question* chip in
  R82b. The operator sees a producer's answerers read-only.
- *Action required* uses the `pending_actions` icon on the app, the web page and the admin page.
- R83 is dropped; R82 is built as R82a then R82b.

### Settled after reviewing the approved designs (2026-10-25)

A review of the designs, the flows and this proposal after G8 raised eleven questions, and the
maintainer chose the recommended answer for each:

- With `textStyle: OTHER`, only `text: OPTIONAL` is valid, and no choice may be labelled "Other"
  (sections 1 and 3).
- An *Other* answer reads "You answered · Other", then "Other: TEXT"; its empty field says "Type
  your answer for Other."; picking it moves the focus to its field (DESIGN.md 10.1 and 10.3).
- A question its producer closed reads "Closed by PRODUCER" in the inbox, and "Closed by PRODUCER ·
  NOTE" on the admin page, whose marker stays *Closed*.
- The notification line never counts or names the *Other* row.
- The admin test dialog keeps *Note* and adds *Typed answer as: Note / Other row* when a note is
  allowed and the question has choices.
- The admin filter is the chip *Question*: Any, Waiting, Answered, Closed, No question.
- A producer's close after `closesAt` succeeds (`200`, `closedBy: TIME`; the command exits 0).
- An event push due after its question was answered or closed is skipped, recorded as `FILTERED`.
- The `answered`, `closed` and `deleted` notices are stored, sent once, and are not delivery records.
- The notices go with NORMAL priority on Android; event pushes keep HIGH.
- Before R82b, the *Other* row, the closed-by-producer card and a 1000-character description are
  drawn; the rest is built from DESIGN.md section 10.
