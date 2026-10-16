A proposal, approved or changed by the maintainer at G8.

# Answering an event: the API proposal (R81)

Status: proposal for the maintainer's approval at G8. Built on the owner's decisions of
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
| `choices` | 0 to 10 items. `id`: `Identifiers.PATTERN`, at most 64, unique in the ask. `label`: 1 to 40 characters, no NUL, unique ignoring case. `description`: optional, at most 200 characters, no NUL; shown under the label in the app and on the web page, and nothing at all when absent or empty (the owner, 2026-10-16). Never in the notification's hint line. |
| `multiple` | `false` by default. `true` = pick one or more; needs at least 2 choices. |
| `text` | `NONE` (default when there are choices), `OPTIONAL` or `REQUIRED`. With no choices it must be `REQUIRED` (a typed question). Typed answers are 1 to 1000 characters. |
| `closesAt` | Optional, with an offset, in the future, at most 30 days ahead. After it nobody can answer. |

- An event without `ask` behaves exactly as today. `ask` is stored with the event (a nullable
  `jsonb` column, V21, like V11's `link`) and joins the idempotency comparison
  (`EventService.sameRequest`).
- The operator's test event (`POST /api/v1/admin/producers/{id}/events`) accepts `ask` too, so the
  feature can be tried from the admin page.
- `ask` is returned in every event response.

## 2. Who may answer

- The producer's **owner**, and the users the owner names as **answerers** of that producer.
  Answerers must be users who can see the producer (owner, public, or on the allow-list).
- To answer an event, a person must also be able to read it today (subscribed to the producer).
  The app says so where it matters: "Stay subscribed to answer".
- **First answer wins**: the first accepted answer closes the question for everyone.
- Everyone else the event reached sees the question read-only, with who answered and what.
- The operator (admin token) acts for no user, so it **never answers**. The admin page shows the
  question and the answer read-only.
- Answerers are a new table `producer_answerers (producer_id, user_id)` beside
  `producer_allowed_users`, under the same producer row lock. A user leaves it when revoked, or when
  they lose sight of a private producer, in the same transaction (the allow-list rule).
- Managed by the owner under `/api/v1/client/producers/{id}`:
  - `PUT|DELETE /answerers/{userId}`;
  - `OwnProducerResponse` gains `answerers [{id, name}]`.
  - The admin API shows them read-only in the producer response: they are the owner's choice.

## 3. Answering: `PUT /api/v1/events/{id}/answer`

Client key or browser cookie (with CSRF), never the admin token (`403`). Body:
`{"choices": ["merge"], "text": "after lunch"}`.

| Answer | When |
|---|---|
| `200` + the event's `answer` | Accepted. The same person sending the same answer again also gets `200` (a doubled tap is harmless). |
| `400` | Unknown choice; no choice where one is needed; several for a single choice; text missing, too long, or not allowed. |
| `403` | This person may not answer this producer's questions. |
| `404` | Not in this person's inbox (not subscribed, deleted, or no such event). |
| `409` + the event's `answer` | Already answered (by someone else, or differently by the same person), or closed (`closesAt` passed). The body says which, so the page shows who answered and what. |

Stored in `event_answers`:
- `event_id`: the primary key, with an FK `ON DELETE CASCADE`. The primary key makes first-answer-wins
  atomic (`INSERT ... ON CONFLICT DO NOTHING`).
- `user_id` and `user_name`: the name is kept as it was, so a later rename doesn't change the record.
- `choice_ids text[]`, `text`, `answered_at`.
- `via`: `APP` or `WEB`, for the admin page's record.

## 4. Reading the answer as the producer: `GET /api/v1/events/{id}/answer?wait=60`

Producer key. Only the producer's own events (`404` otherwise, also once the event is deleted). Any
of the producer's keys may read it.

```json
{"state": "ANSWERED", "answer": {"choices": ["merge"], "text": null,
  "by": {"id": "…", "name": "Rodrigo"}, "at": "2026-10-16T19:02:11Z"}}
```

- `state`: `OPEN`, `ANSWERED` or `CLOSED` (`closesAt` passed with no answer). `answer` is `null`
  unless the state is `ANSWERED`.
- `wait`: 0 (the default) to 60 seconds. It holds the request until the state leaves `OPEN` or the
  wait ends, then returns the current state. A producer that wants to wait longer asks again.
- An event without an ask: `409`.
- Implementation notes for R82:
  - wait on a virtual thread (`@RunOnVirtualThread`, Java 25) with an in-process notifier per event,
    holding no transaction or connection across the wait;
  - at most 200 waits at once; beyond that, answer at once with the current state;
  - the proxy sets no response timeout and the backend sets none (found when the proxy and backend were checked), so 60 s
    passes through Caddy.
- No callback URL, and no feed of all answers for now. A later item adds them if a producer needs
  them.

## 5. What clients see on an event

`EventResponse` gains:
- `ask` (or `null`);
- `answer` (or `null`), as in section 4;
- `answerState`: `OPEN`, `ANSWERED`, `CLOSED`, or `null` without an ask;
- `canAnswer`: whether this caller may answer now. Always `false` for the admin token and producers.

`GET /api/v1/events` gains a filter, `toAnswer=true`: open questions this caller may answer. This is
the app's and web page's *To answer* chip, and the source of a count next to the unread count.
- Opening an event still marks it read.
- "Mark all as read" does not touch questions.
- An open question stays in *To answer* until it's answered or closed, whatever its read state.

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
  answer". Any device can already list users' names, so this reveals nothing new.
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
  - lower-case, accents removed, every run of other characters becomes `-`, trimmed;
  - `choice-N` (its position) when nothing is left;
  - `-2`, `-3` and so on added on a collision.
- **The admin test event** uses the same validation as producers. Errors name the field (`ask.closesAt`
  and so on), so the dialog shows them on the field.
- **"Rodrigo or Ana can answer"** on the admin page may name someone who has since unsubscribed.
  Accepted: the operator doesn't see subscriptions there either.
- **Optional, for the owner at G8:** an `answerState` filter on the admin events list (`OPEN`,
  `ANSWERED`, `CLOSED`, `NONE`) for a *Question* chip. The row markers need no server change.

### Settled at the reviews (step 5)

- **A chip row on the inbox**, app and web: *Unread* and *To answer*. *Unread* is the same switch as
  today's unread-only option in the filter sheet, and the sheet keeps it. It's a design addition
  with no API change, listed for the owner at G8.

## 6. Pushes

Decided by the owner on 2026-10-16: **no action buttons**. Every question is answered by opening the
event, and notifications stay notification messages, built by Android from FCM as today. So the
critical alert, `PushAlertReceiver` and the channel stay as they are.

- **Tag:** every event push gains `android.notification.tag = eventId`, so a later push with the same
  tag replaces it in place.
- **The "Tap to answer" line:** for a question this device's user may answer, the server adds a last
  line to the push body. The server knows who may answer, and the line is built from the ask alone:
  - "Tap to answer · Merge or Hold" for at most 3 single choices;
  - "Tap to answer · 7 choices", or "Tap to answer · pick one or more";
  - "Tap to answer" for a typed question.
  - Up to 3 choices are listed by label, joined as "Merge or Hold", or "Restart, Wait or Ignore".
    When the whole line would pass 80 characters, it says "Tap to answer · 3 choices" instead.

  Tapping opens the event, as today.
- **Per recipient:** the push text is already built per device; the "Tap to answer" line goes only
  to devices whose user may answer. Everyone else gets the event's usual text.
- **When answered, closed or deleted:** SignalHub sends a **data-only** push with `notice=answered`
  (or `closed`, `deleted`) and the `eventId`.
  - It goes to every device the question reached, including the answerer's other devices, but not
    the device that answered.
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
- **Effect on the roadmap:** R83 (notification action buttons) is no longer needed. The notification
  work above is small and fits in R82. At G8, R83 is dropped, or kept only as a deferred candidate.

## 7. Python SDK and the `signalhub` command

- `publish(..., ask=Ask(choices=[Choice("merge", "Merge", description="Squash-merge now"), Choice("hold", "Hold")], multiple=False,
  text="OPTIONAL", closes_at=...))`.
- `wait_answer(event_id, timeout=None)`: repeats 60 s waits until answered, closed, or `timeout`
  passes. Its socket timeout is the wait plus 15 s.
- `signalhub send ... --choice merge=Merge --choice-description merge='Squash-merge now' --choice hold=Hold [--multiple] [--text optional|required]
  [--closes-in 2h]` prints the event ID as today.
- `signalhub wait-answer EVENT_ID [--timeout 30m] [--json]`:
  - prints the chosen choice ids (one per line) and then the text;
  - exits 0 when answered, 5 when closed, 6 when its own timeout passed;
  - so a shell script can branch on it.
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
| Test event from the operator | Asks like any other. The owner and answerers answer it. No producer key reads it unless the producer reads its own events. |

## 9. Compatibility and splitting

- Everything is additive (`feat`, minor): a new optional field, new endpoints, new response fields.
  Old apps ignore `ask` and show the event as today.
- A suggested split for G8:
  - **R82a**: server, SDK and command, with an example; the tag, the "Tap to answer" line and the
    answered notice;
  - **R82b**: answering in the app, on the web page and on the admin page, plus the answerers setting
    and the receiver removing a question's notification on a notice.
  - R83 is dropped (see section 6).
