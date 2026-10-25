# Designs for answering an event

These are the designs R81 made for a producer asking a question in an event and
a person answering it: in the app, from the Android notification, on the users'
web page, and as the operator reads it on the admin page. The server and the
clients are built from them in R82a (the server, the SDK and the command) and
R82b (the screens). The owner approved them at the design gate (G8,
2026-10-25).

Everything is sample data. The host is `signalhub.example`. The people are
Rodrigo (admin and the producers' owner), Ana (mod) and Rui (basic). The
producers (`ci-pipeline`, `homelab-monitor`, `backup-jobs`) and the event IDs
are invented.

A producer **asks** (an optional `ask` on an event: choices, a typed note, a
closing time) and a person **answers**. The producer waits for the answer with
its own key. Nothing in the designs names a producer: a question is generic
choices and text that SignalHub shows and never interprets.

## What is here

| File | What it is |
| --- | --- |
| [WALKTHROUGH.md](WALKTHROUGH.md) | Six flows step by step, with each step linked to its frame, the server changes the designs need, and what was left out. |
| [API-PROPOSAL.md](API-PROPOSAL.md) | The API the designs assume: the `ask` field, who may answer, answering, reading the answer as a producer, the pushes, the SDK and the command. Approved at G8, with the changes of its section 10. |
| `images/` | One preview per frame: 97 images in WebP, in 4 folders. |
| [../users/DESIGN.md](../users/DESIGN.md#10-questions-and-answers-r81) | The design system. Section 10 holds the answer card, its states and exact copy, the inbox lines and chips, the notification line, the answerers setting, the admin markers and the accessibility rules. |
| [../users/source/](../users/source/README.md) | **The drawings themselves**, the source of truth: `App - Answering an event`, `App - Notification actions`, `Web - Answering an event`, `Admin - Questions and answers` and `admin-answers.css`. They live with the users' and the admin drawings because it is one design project and one `vendor/` folder. The images here are previews of them. Where [DESIGN.md section 10](../users/DESIGN.md#10-questions-and-answers-r81) or the G8 section below says otherwise, they win: the drawings still show the older limits and the raised hand. |

The designs were made in the same Claude Design project as the users' and the
admin designs:
<https://claude.ai/design/p/17711c15-5ce6-495c-9841-de8eb831a828>

## How to read it

1. Start with [WALKTHROUGH.md](WALKTHROUGH.md). It follows six flows and links
   each step to its frame.
2. Use [../users/DESIGN.md](../users/DESIGN.md#10-questions-and-answers-r81) to
   check a rule, a component, a string or a duration.
3. Each image has a frame id in its top left (`1a`, `2e`, `Q1b`) and a note
   under the screen. The note has the exact copy and the rules. Ids are the same
   in the project and in the sources. They are unique within a folder, not across
   folders (`1a` is the app's answer card in `app-answering/` and the notification
   of a question in `notification/`).
4. Frames are dark unless they are `5a` (app), `1i` (notification), `1o` (web)
   or `Q1g` (admin), the one light frame of each page.
5. A frame that says "Not chosen" is an option the owner did not pick. It is
   kept as drawn for the record.
6. The app and notification frames are 390 px wide. The web page's desktop
   frames are about 1280 px wide, its phone frames 390 px. The admin page's pane
   is 480 px, its dialogs 760 px, its list 1440 px.

## The owner chose

| Question | Choice | Not chosen |
| --- | --- | --- |
| Who answers (2026-10-16) | The producer's owner, and the users the owner names as answerers of that producer. The first answer wins and closes the question. Everyone else the event reached sees it read-only, with who answered and what. The operator never answers. | Nothing else was drawn. |
| How the producer reads it | Ask and wait: the producer reads the answer with its own key and may wait on it for a while. | Nothing else was drawn (no callback URL). |
| Kinds of reply | One choice, several choices, a typed answer, and a choice with an optional note or an *Other* row (decided at G8). Up to 10 choices. | Nothing else was drawn. |
| Answering in the event | **A**: an answer card under the message. Select, then *Send answer*. The owner's reason: it is closest to Claude Code's prompt. | [B](images/app-answering/1b-option-b-an-answer-button-that.webp), an *Answer* button that opens a bottom sheet ([1b1](images/app-answering/1b1-option-b-the-sheet-after-tapping.webp)). [C](images/app-answering/1c-option-c-a-sticky-area-here.webp), a sticky area below the event with one button per choice, which falls back to one *Answer* button when a choice has a description, there are more than 3 choices, it is a multiple choice or it takes text ([1c2](images/app-answering/1c2-option-c-direct-buttons-no-descriptions.webp), [1c1](images/app-answering/1c1-option-c-the-confirmation-after-tapping.webp)). |
| Notification buttons | **None.** A notification is answered by opening the event. It gains a last line, *Tap to answer*. This made the planned notification-buttons item unnecessary. | Choice buttons in the notification. They were planned and dropped before anything was drawn. |
| When a question is answered, closed or deleted | **The notification is removed**, not replaced. A replacement would pop up again, sound again and bring back a card the person swiped away. The outcome shows in the inbox and the event. See [1d](images/notification/1d-answered-the-notification-goes.webp), [1e](images/notification/1e-closed-the-notification-goes.webp), [1e2](images/notification/1e2-deleted-the-notification-goes.webp). | Replacing the notification in place. |
| Choice descriptions | A choice may have an optional description of at most 1000 characters (G8; 200 before). It shows under the label in the app and on the web page, and not at all when empty. Never in the notification. | Nothing else was drawn. |

### Not chosen

- **Option B**, an *Answer* button that opens a sheet: [1b](images/app-answering/1b-option-b-an-answer-button-that.webp), [1b1](images/app-answering/1b1-option-b-the-sheet-after-tapping.webp). The
  event stays as it is and the button is the same for 2 or 7 choices, but the
  choices and descriptions are hidden behind a tap and the sheet covers the
  message.
- **Option C**, a sticky area with one button per choice: [1c](images/app-answering/1c-option-c-a-sticky-area-here.webp), [1c2](images/app-answering/1c2-option-c-direct-buttons-no-descriptions.webp), [1c1](images/app-answering/1c1-option-c-the-confirmation-after-tapping.webp).
  The fastest path for two plain choices, but a button can hold no description,
  it needs its own confirmation, and it falls back to B's sheet for everything
  else, so the screen has two layouts.

## Decided at G8 (2026-10-25)

The maintainer approved the designs and the proposal. The changes are listed in
[API-PROPOSAL.md](API-PROPOSAL.md#10-decided-at-g8-2026-10-25) and in
[DESIGN.md section 10](../users/DESIGN.md#10-questions-and-answers-r81), which
supersede frames that show the older limits: labels up to 100 characters,
descriptions up to 1000, typed answers up to 3000; a note or an *Other* row, as
the producer chooses; the producer closes a question answered elsewhere;
Ctrl+Enter sends on the web page; the *Question* filter on the admin page;
`pending_actions` for *Action required* everywhere. The notification line stays
within 80 characters, and the *Unread* and *To answer* chips are approved.

## Frames superseded by the text

Some frames were drawn before G8 and are not redrawn yet. Where a frame and
[DESIGN.md section 10](../users/DESIGN.md#10-questions-and-answers-r81)
disagree, section 10 wins. Until they are redrawn, read them this way:

- **Every app and web frame with *Action required*** (app 1a to 1c2, 2b to 2q
  but not 2i and 2m, 3a, 3b, 5a; web 1a to 1q, 2a, 2b, 3a to 3c): the raised
  hand is `pending_actions` (DESIGN.md 3.1).
- **App 1a, 1b1, 2c, 2d, 2k, 2n, 2p, 5a; web 1a to 1d, 1i, 1k to 1o, 3b:** a
  counter `/ 1000` is `/ 3000`; too long reads `3043 / 3000`, and a caption's
  1000 for a typed answer is 3000.
- **App 2a, 2p; notification 1b2; admin D1b:** labels are up to 100 characters
  (not 40) and descriptions up to 1000 (not 200), with the dialog's counters
  `n / 100` and `n / 1000`. The 80-character line of 1b2 is settled, not a guess.
- **Web 1n:** "There is no shortcut that sends" is out of date: Ctrl+Enter
  (Cmd+Enter on a Mac) sends, Enter alone does not (10.8).
- **Web 1h, 1p:** the read-only card is the disabled list of 10.2, as in app 2h,
  not a sentence.
- **Web 1a to 1q:** the filled *To answer* chip is an unselected chip; a selected
  chip has a check and filters the list (10.4).
- **Web 2a, 2b:** the answer card is cut off; it is the full card of web 1a, with
  the note, *Send answer* and *Open link*.
- **Admin L1, D2c, G1:** the filter chip is *Question*, a normal chip built in
  R82b and in the filter row of every list frame, not a dashed *Answer state*.
  G1's open gap was settled at G8.
- **No frame yet** for the *Other* row, a question closed by its producer, the
  Ctrl+Enter tooltip, the *Question* filter's menu, a 100-character label, a
  1000-character description, a 3000-character answer, or the dialog's
  note-or-*Other* control. Section 10 describes them. Before R82b starts, the
  *Other* row (app and web page), the closed-by-producer card and a
  1000-character description are drawn (the maintainer, 2026-10-25); the rest
  is built from section 10.

## What the images show

### The app: answering an event

Folder `images/app-answering/`, 33 images. Drawn in `App - Answering an event`. Three options for the answer in the event detail (A chosen, B and C kept for the record), the states of a question, the inbox with its chips, the answerers setting on your own producer, and one light frame. Frames are 390 px wide.

- [1a](images/app-answering/1a-option-a-an-answer-card-under.webp): Option A: an answer card under the message
- [1b](images/app-answering/1b-option-b-an-answer-button-that.webp): Option B: an Answer button that opens a sheet
- [1b1](images/app-answering/1b1-option-b-the-sheet-after-tapping.webp): Option B: the sheet after tapping Answer
- [1c](images/app-answering/1c-option-c-a-sticky-area-here.webp): Option C: a sticky area, here the fallback (a choice has a description)
- [1c2](images/app-answering/1c2-option-c-direct-buttons-no-descriptions.webp): Option C: direct buttons, no descriptions
- [1c1](images/app-answering/1c1-option-c-the-confirmation-after-tapping.webp): Option C: the confirmation after tapping Restart
- [2a](images/app-answering/2a-seven-choices-single-choice.webp): Seven choices, single choice
- [2b](images/app-answering/2b-multiple-choice.webp): Multiple choice
- [2c](images/app-answering/2c-a-typed-question-only-with-the.webp): A typed question only, with the character counter
- [2d](images/app-answering/2d-sending.webp): Sending
- [2e](images/app-answering/2e-answered-by-you.webp): Answered by you
- [2e2](images/app-answering/2e2-a-typed-question-answered.webp): A typed question, answered
- [2f](images/app-answering/2f-answered-by-someone-else.webp): Answered by someone else
- [2g](images/app-answering/2g-closed-with-no-answer.webp): Closed with no answer
- [2h](images/app-answering/2h-open-but-you-may-not-answer.webp): Open, but you may not answer
- [2i](images/app-answering/2i-you-own-the-producer-but-unsubscribed.webp): You own the producer but unsubscribed
- [2j](images/app-answering/2j-it-closes-soon.webp): It closes soon
- [2k](images/app-answering/2k-send-failed-offline-or-server-error.webp): Send failed (offline or server error)
- [2l](images/app-answering/2l-someone-answered-first-while-you-were.webp): Someone answered first while you were choosing
- [2l2](images/app-answering/2l2-it-closed-while-you-were-choosing.webp): It closed while you were choosing
- [2m](images/app-answering/2m-the-event-was-deleted-meanwhile.webp): The event was deleted meanwhile
- [2n](images/app-answering/2n-field-error-the-text-is-too.webp): Field error: the text is too long
- [2o](images/app-answering/2o-field-error-nothing-picked.webp): Field error: nothing picked
- [2p](images/app-answering/2p-a-choice-with-a-200character-description.webp): A choice with a long description
- [2q](images/app-answering/2q-multiple-choice-with-descriptions.webp): Multiple choice with descriptions
- [3a](images/app-answering/3a-inbox-a-question-to-answer-waiting.webp): Inbox: a question to answer, waiting, answered, closed
- [3b](images/app-answering/3b-the-to-answer-filter-on.webp): The To answer filter on
- [3c](images/app-answering/3c-the-to-answer-filter-nothing-left.webp): The To answer filter, nothing left
- [4a](images/app-answering/4a-your-producer-who-can-answer-one.webp): Your producer: Who can answer, one person added
- [4b](images/app-answering/4b-nobody-added-yet.webp): Nobody added yet
- [4c](images/app-answering/4c-add-people-who-can-answer.webp): Add people who can answer
- [4d](images/app-answering/4d-removing-a-person-the-confirmation.webp): Removing a person: the confirmation
- [5a](images/app-answering/5a-light-theme-the-answer-card-1a.webp): Light theme: the answer card (1a)

### The Android notification

Folder `images/notification/`, 12 images. Drawn in `App - Notification actions`. The notification of a question: the "Tap to answer" line, its removal when the question is answered, closed or deleted, a critical question, a bundle, and one light frame. Frames are 390 px wide.

- [1a](images/notification/1a-a-question-you-may-answer.webp): A question you may answer
- [1b](images/notification/1b-the-last-line-for-each-kind.webp): The last line for each kind of question
- [1b2](images/notification/1b2-long-labels.webp): Long labels
- [1c](images/notification/1c-a-question-you-may-not-answer.webp): A question you may not answer
- [1d](images/notification/1d-answered-the-notification-goes.webp): Answered: the notification goes
- [1e](images/notification/1e-closed-the-notification-goes.webp): Closed: the notification goes
- [1e2](images/notification/1e2-deleted-the-notification-goes.webp): Deleted: the notification goes
- [1f](images/notification/1f-a-critical-question.webp): A critical question
- [1g](images/notification/1g-several-questions-at-once.webp): Several questions at once
- [1g2](images/notification/1g2-pulled-open.webp): Pulled open
- [1h](images/notification/1h-tapping-one.webp): Tapping one
- [1i](images/notification/1i-light-theme-the-question-card.webp): Light theme: the question card

### The web page: answering an event

Folder `images/web-answering/`, 29 images. Drawn in `Web - Answering an event`. The desktop event pane with the answer card and its states, the inbox with the To answer chip, the answerers setting, the phone-width frames (3a to 3c and 4e) and one light frame. Desktop frames are about 1280 px wide.

- [1a](images/web-answering/1a-the-question-a-single-choice-with.webp): The question: a single choice with a description, an optional note
- [1b](images/web-answering/1b-multiple-choice-with-descriptions.webp): Multiple choice with descriptions
- [1c](images/web-answering/1c-a-typed-question-only.webp): A typed question only
- [1d](images/web-answering/1d-sending.webp): Sending
- [1e](images/web-answering/1e-you-answered.webp): You answered
- [1f](images/web-answering/1f-someone-else-answered.webp): Someone else answered
- [1g](images/web-answering/1g-closed-with-no-answer.webp): Closed with no answer
- [1h](images/web-answering/1h-open-but-you-may-not-answer.webp): Open, but you may not answer
- [1i](images/web-answering/1i-send-failed.webp): Send failed
- [1j](images/web-answering/1j-someone-answered-first.webp): Someone answered first
- [1k](images/web-answering/1k-it-closes-soon.webp): It closes soon
- [1l](images/web-answering/1l-field-error-the-text-is-too.webp): Field error: the text is too long
- [1m](images/web-answering/1m-field-error-nothing-picked.webp): Field error: nothing picked
- [1n](images/web-answering/1n-keyboard-the-focus-ring-and-the.webp): Keyboard: the focus ring and the keys
- [1o](images/web-answering/1o-1a-in-the-light-theme.webp): 1a in the light theme
- [1p](images/web-answering/1p-a-403-on-send-the-page.webp): A 403 on Send: the page re-reads and shows the read-only card
- [1q](images/web-answering/1q-you-answered-a-typed-question.webp): You answered a typed question
- [2a](images/web-answering/2a-inbox-a-question-to-answer-answered.webp): Inbox: a question to answer, answered, closed, waiting (an admin's rail)
- [2b](images/web-answering/2b-the-to-answer-chip-on.webp): The To answer chip on
- [2c](images/web-answering/2c-the-to-answer-chip-on-nothing.webp): The To answer chip on, nothing left
- [3a](images/web-answering/3a-inbox-with-the-chip-and-the.webp): Inbox with the chip and the question lines
- [3b](images/web-answering/3b-the-event-screen-with-the-answer.webp): The event screen with the answer card
- [3c](images/web-answering/3c-the-answered-state.webp): The answered state
- [4a](images/web-answering/4a-your-producer-who-can-answer-one.webp): Your producer: Who can answer, one person added
- [4b](images/web-answering/4b-nobody-added-yet.webp): Nobody added yet
- [4c](images/web-answering/4c-add-people-who-can-answer-the.webp): Add people who can answer: the dialog
- [4d](images/web-answering/4d-removing-a-person-the-confirmation.webp): Removing a person: the confirmation
- [4f](images/web-answering/4f-your-producer-unsubscribed-stay-subscribed-to.webp): Your producer, unsubscribed: Stay subscribed to answer
- [4e](images/web-answering/4e-your-producer-at-phone-width-one.webp): Your producer at phone width, one person added

### The admin page: questions and answers

Folder `images/admin/`, 23 images. Drawn in `Admin - Questions and answers`. The operator reads a question and its answer (it never answers), the list markers, the delete confirmations, the Send a test event dialog with an "Ask for an answer" section, and the producer's read-only "Who can answer". Frames are 390, 480, 760, 900 or 1440 px wide.

- [Q1](images/admin/q1-open-waiting-for-an-answer.webp): Open: waiting for an answer
- [Q1b](images/admin/q1b-answered-in-the-app-with-a.webp): Answered in the app, with a note
- [Q1c](images/admin/q1c-several-choices-answered-on-the-web.webp): Several choices, answered on the web page
- [Q1d](images/admin/q1d-a-typed-question-answered.webp): A typed question, answered
- [Q1e](images/admin/q1e-closed-with-no-answer.webp): Closed with no answer
- [Q1f](images/admin/q1f-the-answerer-was-revoked-later.webp): The answerer was revoked later
- [Q1g](images/admin/q1g-q1b-in-the-light-theme.webp): Q1b in the light theme
- [Q3](images/admin/q3-delete-an-event-that-asks-still.webp): Delete an event that asks, still open
- [Q3b](images/admin/q3b-delete-several-events-some-ask.webp): Delete several events, some ask
- [Q2](images/admin/q2-phone-the-detail-with-an-answered.webp): Phone: the detail with an answered question
- [L1](images/admin/l1-the-list-with-questions.webp): The list with questions
- [D1q](images/admin/d1q-the-dialog-with-the-section-folded.webp): The dialog with the section folded (the default)
- [D1a](images/admin/d1a-the-section-opened-for-the-first.webp): The section opened for the first time
- [D1b](images/admin/d1b-a-question-filled-in.webp): A question filled in
- [D1c](images/admin/d1c-error-two-choices-with-the-same.webp): Error: two choices with the same label
- [D1d](images/admin/d1d-error-more-than-10-choices.webp): Error: more than 10 choices
- [D1e](images/admin/d1e-error-no-choices-so-the-note.webp): Error: no choices, so the note must be required
- [D1f](images/admin/d1f-error-one-or-more-with-a.webp): Error: one or more with a single choice
- [D1g](images/admin/d1g-closes-at-a-date-and-a.webp): Closes at: a date and a time
- [D2c](images/admin/d2c-sent-the-snack-bar-links-to.webp): Sent: the snack bar links to the event
- [P21](images/admin/p21-who-can-answer-the-owner-and.webp): Who can answer: the owner and answerers
- [P22](images/admin/p22-who-can-answer-only-the-owner.webp): Who can answer: only the owner
- [G1](images/admin/g1-seven-gaps-six-settled-one-open.webp): Seven gaps: six settled, one open
