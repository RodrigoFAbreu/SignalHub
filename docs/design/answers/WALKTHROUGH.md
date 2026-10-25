# Walkthrough of answering an event

This walks six flows step by step: how a producer asks, how the owner answers,
how an answerer answers on the web page, what happens when someone else answered
first, how a question closes, and how the operator looks at a question and
sends a test one. Each step links to the frame that draws it. The frames are in
`images/`. Every frame has its id in its top left and a note under the screen
with the exact copy and the rules.

All people, hosts and keys are sample data: `signalhub.example`, Rodrigo
(admin, the producers' owner), Ana (mod) and Rui (basic). The example question
is *Merge R82 into main?* from the producer `ci-pipeline`, with the choices
*Merge* and *Hold*.

Contents:

1. [A producer asks and waits](#1-a-producer-asks-and-waits)
2. [The owner answers in the app, from a notification](#2-the-owner-answers-in-the-app-from-a-notification)
3. [An answerer answers on the web page](#3-an-answerer-answers-on-the-web-page)
4. [Someone else answered first](#4-someone-else-answered-first)
5. [The question closes](#5-the-question-closes)
6. [The operator looks at a question and sends a test question](#6-the-operator-looks-at-a-question-and-sends-a-test-question)
7. [The server changes and what was left out](#7-the-server-changes-and-what-was-left-out)

## 1. A producer asks and waits

A producer adds an optional `ask` to an event: up to 10 choices (each with an
optional description), pick one or several, an optional or required typed note,
and a closing time. It then waits for the answer with its own key (a long poll,
or `signalhub wait-answer`). The rules and the fields are in
[API-PROPOSAL.md](API-PROPOSAL.md#1-asking-a-new-optional-field-on-post-apiv1events).
There is no screen for the producer: it is an API client.

1. **The push reaches the owner's phone.** The notification is the event's own
   (title and message, built by Android from the push), with one new last line,
   which tells the person how to answer. It is shown when the card is expanded.
   ![1a: A question you may answer](images/notification/1a-a-question-you-may-answer.webp)
2. **The line says what the question is.** Up to 3 single choices list their
   labels; more than 3 say how many; a multiple choice says "pick one or more";
   a typed question says only "Tap to answer". A line that would pass 80
   characters says "Tap to answer · 3 choices". [1b](images/notification/1b-the-last-line-for-each-kind.webp), [1b2](images/notification/1b2-long-labels.webp)
3. **Only people who may answer get the line.** Someone the event reached
   read-only gets the event's usual text. [1c](images/notification/1c-a-question-you-may-not-answer.webp)
4. **A critical question** keeps today's alert (SignalHub's own sound, volume
   and vibration); the line is the same. [1f](images/notification/1f-a-critical-question.webp)
5. **Several questions** bundle as Android bundles any app's notifications.
   [1g](images/notification/1g-several-questions-at-once.webp), [1g2](images/notification/1g2-pulled-open.webp)
6. **In the inbox** the row of an open question has a second line, "To answer"
   (with the closing time when there is one), and the *To answer* chip counts
   it. [3a](images/app-answering/3a-inbox-a-question-to-answer-waiting.webp) A person who can only read it sees "Waiting for Rodrigo".
7. **While it waits** the operator sees the same question on the admin page,
   read-only: "Waiting for an answer · closes 09:00 · Rodrigo or Ana can answer".
   [Q1](images/admin/q1-open-waiting-for-an-answer.webp)

## 2. The owner answers in the app, from a notification

The owner is Rodrigo. Tapping the notification opens the event. Nothing is sent
from the notification.

1. **Tap the notification.** It opens the event on its answer card. [1h](images/notification/1h-tapping-one.webp)
2. **The card under the message** is headed "Your answer". It says "Pick one.
   It goes to ci-pipeline and can't be changed once sent." Each choice is a
   48 dp row with its description under the label when it has one, then
   "Note (optional)" with a counter, then *Send answer*. [1a](images/app-answering/1a-option-a-an-answer-card-under.webp)
3. **Choosing is not sending.** *Send answer* is the confirmation, so there is no
   dialog. The button stays enabled; with nothing picked it says "Pick an answer
   to send." [2o](images/app-answering/2o-field-error-nothing-picked.webp)
4. **Other kinds of question** use the same card:
   - seven choices, one of them: [2a](images/app-answering/2a-seven-choices-single-choice.webp);
   - several choices, with checkboxes and "Pick one or more": [2b](images/app-answering/2b-multiple-choice.webp), [2q](images/app-answering/2q-multiple-choice-with-descriptions.webp);
   - a typed question, whose field is required: [2c](images/app-answering/2c-a-typed-question-only-with-the.webp);
   - a long description that wraps and is never cut: [2p](images/app-answering/2p-a-choice-with-a-200character-description.webp).
5. **A note that is too long** shows its error as soon as the text passes 3000
   characters, and the text is never cut. [2n](images/app-answering/2n-field-error-the-text-is-too.webp)
6. **Sending.** The choices and the note are dimmed, and the button reads
   "Sending". Leaving the screen does not cancel the send. [2d](images/app-answering/2d-sending.webp)
7. **The card becomes the result:** "You answered · Merge · 19:02", with the note
   under it. [2e](images/app-answering/2e-answered-by-you.webp) A typed question reads "You answered · ‘after lunch’".
   [2e2](images/app-answering/2e2-a-typed-question-answered.webp)
8. **The notification goes.** The question's card is removed on every device that
   had it, with no heads-up and no sound. The answerer's other devices lose it
   too. [1d](images/notification/1d-answered-the-notification-goes.webp)
9. **The inbox** shows "You answered · Merge", and the *To answer* count drops.
   With the chip on and nothing left it says "Nothing to answer".
   [3b](images/app-answering/3b-the-to-answer-filter-on.webp), [3c](images/app-answering/3c-the-to-answer-filter-nothing-left.webp)
10. **If sending fails** (offline or a server error), a snackbar says "Answer not
    sent" with *Retry*, and the choice and the note are kept. [2k](images/app-answering/2k-send-failed-offline-or-server-error.webp)
11. **Light theme:** [5a](images/app-answering/5a-light-theme-the-answer-card-1a.webp); the notification: [1i](images/notification/1i-light-theme-the-question-card.webp).

The owner also decides who else may answer, on the producer's own screen.

12. **Who can answer.** The owner is the first row and can't be removed. Added
    people get a close button, "Remove Ana". [4a](images/app-answering/4a-your-producer-who-can-answer-one.webp)
13. **Nobody added yet:** "Only you can answer this producer's questions."
    [4b](images/app-answering/4b-nobody-added-yet.webp)
14. **Add people.** The picker lists only people who can see the producer, and
    says they also need to be subscribed. [4c](images/app-answering/4c-add-people-who-can-answer.webp)
15. **Remove a person.** A confirmation, because it changes what someone else
    can do. Answers already given stay. [4d](images/app-answering/4d-removing-a-person-the-confirmation.webp)

## 3. An answerer answers on the web page

Ana is an answerer of `ci-pipeline`, signed in on the users' web page. The card
is the app's option A at the web page's width.

1. **The inbox** has two chips, *Unread* and *To answer 2*, and a question's row
   says "To answer · Closes 09:00". A person who never gets questions never sees
   the chip. [2a](images/web-answering/2a-inbox-a-question-to-answer-answered.webp)
2. **The chip on** lists only the open questions this person may answer.
   [2b](images/web-answering/2b-the-to-answer-chip-on.webp), [2c](images/web-answering/2c-the-to-answer-chip-on-nothing.webp)
3. **The event pane** shows the card under the message and above *Open link*.
   [1a](images/web-answering/1a-the-question-a-single-choice-with.webp)
4. **Other kinds:** several choices [1b](images/web-answering/1b-multiple-choice-with-descriptions.webp); a typed question [1c](images/web-answering/1c-a-typed-question-only.webp).
5. **Keyboard.** A group of radios is one tab stop; the arrow keys move and check;
   Space checks. Tab goes on to the note and then to *Send answer*. Enter in the
   note does not send. [1n](images/web-answering/1n-keyboard-the-focus-ring-and-the.webp)
6. **Mistakes** are shown under the field: [1l](images/web-answering/1l-field-error-the-text-is-too.webp), [1m](images/web-answering/1m-field-error-nothing-picked.webp).
7. **Sending** and **the result**: [1d](images/web-answering/1d-sending.webp), [1e](images/web-answering/1e-you-answered.webp). A typed answer: [1q](images/web-answering/1q-you-answered-a-typed-question.webp).
8. **If sending fails**, a snackbar with *Retry* keeps the choice and the note.
   [1i](images/web-answering/1i-send-failed.webp)
9. **A `403` on Send** (the owner removed this person while the card was open):
   the page re-reads the event and shows the read-only card with "Your answer
   wasn't sent." [1p](images/web-answering/1p-a-403-on-send-the-page.webp)
10. **Someone the question reached read-only** sees the choices as a list with no
    controls and a title naming who can answer. [1h](images/web-answering/1h-open-but-you-may-not-answer.webp)
11. **At phone width** the rail is a bottom bar and the card fills the screen:
    [3a](images/web-answering/3a-inbox-with-the-chip-and-the.webp), [3b](images/web-answering/3b-the-event-screen-with-the-answer.webp), [3c](images/web-answering/3c-the-answered-state.webp).
12. **Light theme:** [1o](images/web-answering/1o-1a-in-the-light-theme.webp).

The owner sets who can answer on the web page too. The section is the app's, in
the producer's pane: [4a](images/web-answering/4a-your-producer-who-can-answer-one.webp), [4b](images/web-answering/4b-nobody-added-yet.webp), [4c](images/web-answering/4c-add-people-who-can-answer-the.webp), [4d](images/web-answering/4d-removing-a-person-the-confirmation.webp), [4e](images/web-answering/4e-your-producer-at-phone-width-one.webp). An owner who
unsubscribed from their own producer is told "Stay subscribed to answer" where
the switch is. [4f](images/web-answering/4f-your-producer-unsubscribed-stay-subscribed-to.webp)

## 4. Someone else answered first

Two people may answer, and the first answer wins. The server decides by the
event's primary key, so the second gets `409` with the winner's answer.

1. **Open on a second device or tab.** Ana answers while Rodrigo is choosing.
2. **Rodrigo taps *Send answer*.** The card swaps at once to
   "Ana answered first: Hold", with "Your answer wasn't sent." No error colour and
   no retry; their choice and note are dropped. App: [2l](images/app-answering/2l-someone-answered-first-while-you-were.webp). Web: [1j](images/web-answering/1j-someone-answered-first.webp).
3. **If it was the same person on another device,** it reads "You answered ·
   Merge" if the answers are equal, and "You already answered: Merge. Your new
   answer wasn't sent." if they differ.
4. **Everyone else the event reached** sees the result read-only: "Ana answered ·
   Hold · 18:55", "Sent to ci-pipeline. Nobody else can answer now." The name is
   the one stored with the answer, even if Ana is renamed later. App: [2f](images/app-answering/2f-answered-by-someone-else.webp).
   Web: [1f](images/web-answering/1f-someone-else-answered.webp).
5. **A card that was open** turns into the result by itself: the web page re-reads
   an open event when its tab regains focus and after any `409`, and the app
   re-reads it on resume.
6. **Their notifications** are removed on every device. [1d](images/notification/1d-answered-the-notification-goes.webp)
7. **A person who may not answer** sees the question while it is open:
   [2h](images/app-answering/2h-open-but-you-may-not-answer.webp). The line names who can answer: "Rodrigo answers this", "Rodrigo or
   Ana can answer", "Rodrigo, Ana or Rui can answer".

## 5. The question closes

A question may have a closing time (at most 30 days ahead). After it nobody can
answer.

1. **The card says when.** "Closes at 09:00", grey. In the last hour it adds "in
   12 min" and turns to the error colour with a clock icon. App: [2j](images/app-answering/2j-it-closes-soon.webp).
   Web: [1k](images/web-answering/1k-it-closes-soon.webp).
2. **The time passes.** The question closes and the server sends a data-only
   notice. Every device removes the question's notification, with nothing shown
   or played. [1e](images/notification/1e-closed-the-notification-goes.webp)
3. **The card becomes** "Closed · nobody answered in time", "It closed on 17 Oct
   at 09:00. ci-pipeline got no answer." It is not an error. App: [2g](images/app-answering/2g-closed-with-no-answer.webp).
   Web: [1g](images/web-answering/1g-closed-with-no-answer.webp).
4. **If it closes while someone is choosing,** *Send answer* gets `409` and the
   card swaps to "Closed while you were choosing · nobody can answer it now".
   The choice and the note are dropped. [2l2](images/app-answering/2l2-it-closed-while-you-were-choosing.webp)
5. **If the event is deleted** (by the operator or by retention), the question and
   any answer go with it. A card still on screen opens "This event isn't in your
   inbox any more". [2m](images/app-answering/2m-the-event-was-deleted-meanwhile.webp), and the notification is removed:
   [1e2](images/notification/1e2-deleted-the-notification-goes.webp)
6. **A phone that was offline** keeps the card until the notice arrives. Tapping
   it opens the event in its current state. The limits of removal are written in
   the notification page's second turn.
7. **The producer** reads the same state, `CLOSED`, with its own key. The inbox
   row says "Closed · nobody answered". [3a](images/app-answering/3a-inbox-a-question-to-answer-waiting.webp)

## 6. The operator looks at a question and sends a test question

The operator is the host, signed in with the admin token. The token acts for no
user, so the operator **never answers**: the admin page shows the question and
its answer read-only.

1. **The list.** An event that asks has a small word under its title: *Waiting*,
   *Answered* or *Closed*. The page never says "To answer". [L1](images/admin/l1-the-list-with-questions.webp)
2. **An open question.** In the event pane, under the message, the question as
   the producer asked it (pick one, note, closing time, each choice with its
   description), and "Waiting for an answer · closes 09:00 · Rodrigo or Ana can
   answer". The admin page cannot answer. [Q1](images/admin/q1-open-waiting-for-an-answer.webp)
3. **An answered question** says who answered, when and where ("in the app" or
   "on the web page"), the labels chosen and the note. [Q1b](images/admin/q1b-answered-in-the-app-with-a.webp) Several
   choices: [Q1c](images/admin/q1c-several-choices-answered-on-the-web.webp). A typed question: [Q1d](images/admin/q1d-a-typed-question-answered.webp).
4. **A closed question** has no answer block. [Q1e](images/admin/q1e-closed-with-no-answer.webp)
5. **An answerer who was revoked later** keeps the name stored with the answer,
   with a *Revoked* tag. [Q1f](images/admin/q1f-the-answerer-was-revoked-later.webp)
6. **Light theme and phone:** [Q1g](images/admin/q1g-q1b-in-the-light-theme.webp), [Q2](images/admin/q2-phone-the-detail-with-an-answered.webp).
7. **Deleting an event that asks** adds one sentence to the confirmation: "Its
   question and any answer are deleted too." [Q3](images/admin/q3-delete-an-event-that-asks-still.webp), [Q3b](images/admin/q3b-delete-several-events-some-ask.webp)
8. **Who can answer, on a producer.** The producer's pane lists the owner and the
   answerers read-only; the owner sets them in the app. [P21](images/admin/p21-who-can-answer-the-owner-and.webp), [P22](images/admin/p22-who-can-answer-only-the-owner.webp)
9. **Send a test question.** The *Send a test event* dialog has one folded section at
   its foot, "Ask for an answer", so a plain test event is as short as before.
   [D1q](images/admin/d1q-the-dialog-with-the-section-folded.webp) Opened for the first time: [D1a](images/admin/d1a-the-section-opened-for-the-first.webp). Filled in, with
   choices, descriptions, ids derived from the labels, a note rule and a closing
   time: [D1b](images/admin/d1b-a-question-filled-in.webp)
10. **Mistakes name the field:** [D1c](images/admin/d1c-error-two-choices-with-the-same.webp), [D1d](images/admin/d1d-error-more-than-10-choices.webp), [D1e](images/admin/d1e-error-no-choices-so-the-note.webp), [D1f](images/admin/d1f-error-one-or-more-with-a.webp). A closing time is a
    date and a time in the operator's time zone: [D1g](images/admin/d1g-closes-at-a-date-and-a.webp).
11. **Sent.** The snack bar links to the new event and says who was asked. The
    operator reads the answer in the pane as it arrives. [D2c](images/admin/d2c-sent-the-snack-bar-links-to.webp)
12. **Gaps found while drawing**, six settled and one open: [G1](images/admin/g1-seven-gaps-six-settled-one-open.webp).

## 7. The server changes and what was left out

### The server changes the designs need

The designs assume the API in [API-PROPOSAL.md](API-PROPOSAL.md). In short:

- `ask` on `POST /api/v1/events` and on the operator's test event, stored with
  the event and returned in every event response with `answer`, `answerState`
  and `canAnswer`, and `ask.whoCanAnswer` (the owner first).
- `PUT /api/v1/events/{id}/answer`, first answer wins, with `400`, `403`, `404`
  and `409` (already answered, or closed).
- `GET /api/v1/events/{id}/answer?wait=60` for the producer's key.
- A `toAnswer=true` filter on the event list, and the answerers of a producer
  (`PUT` and `DELETE` under `/api/v1/client/producers/{id}/answerers/{userId}`).
- Pushes: a tag per event, a last "Tap to answer" line only for people who may
  answer, and a data-only notice (`answered`, `closed`, `deleted`) that makes the
  app remove the question's notification. Closing is scheduled at `closesAt`.
- The Python package and the `signalhub` command: `ask` on publish, `wait_answer`,
  `signalhub wait-answer`.
- Optional, for the owner: an `answerState` filter on the admin events list
  ([L1](images/admin/l1-the-list-with-questions.webp)).

### What the owner decided

Answering is option A. Notifications have no buttons and a question's
notification is removed when it is decided. Choices may have descriptions. See
[README.md](README.md#the-owner-chose) and the options kept for the record in
[Not chosen](README.md#not-chosen).

### What was left out

- **Notification action buttons** and an *Answers* notification channel. Every
  question is answered by opening the event.
- **Replacing a notification** with the outcome. Removing it avoids a second
  alert and a card the person had swiped away.
- **A callback URL** for the producer, and a feed of all answers. A producer
  waits for the answer of its own event.
- **Changing an answer.** An answer is final; the same answer sent twice is
  accepted.
- **The operator answering.** The admin token acts for no user.
- **An "Other" row** instead of the note, as in Claude Code's prompt. Not decided.
- **Offline answering.** An answer that cannot be sent is kept on the screen with
  *Retry*; nothing is queued.
- **Showing who has subscribed** in the answerers picker: the owner does not see
  subscriptions, so the picker says people need to be subscribed.
- **Clickable prototypes.** The drawings are plain frames.
