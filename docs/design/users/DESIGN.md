# SignalHub design system

This is the design system for SignalHub's app and web page. It records the
look the released app already has (version 2.26.6) and the patterns added for
users in R64. Section 9 adds what R73 drew for the operator's admin page
(`/admin/`) and the two rules it changed for the web page. Section 10 adds what
R81 drew for a producer's question and the answer to it. New screens extend
it. They do not restyle it.

The source is the `SignalHub Design System` page in the Claude Design project.
Section images of that page are in `images/design-system/`, and the Admin page
section (R73) is in `../admin/images/design-system-admin/`. A few frames show
the same tokens in the light theme (`images/light-theme/`).

## 1. Rules, in order of precedence

When two sources disagree, the first one in this list wins.

1. The maintainer's words.
2. This file.
3. The platform's conventions: Material 3 for the Android app, the Web
   Interface Guidelines for the web page.
4. A design skill's own defaults. No skill changes the palette, type or
   patterns on its own.

Working rules:

- **Extend, do not restyle.** A new screen reuses the components here. A new
  component is added here first, from the same tokens.
- **Restraint.** Product screens are for operating, not persuading. At most
  one expressive element per screen, and only where this file allows it.
- **Touch and type.** Touch targets are 48 dp (Material), not 44 pt. Text uses
  the Material type scale with Roboto. No size is picked per screen.
- **Summaries.** Folded groups and list rows sum up their values in one line
  joined with middle dots (`Info · Normal · backup-jobs`). It is SignalHub's
  own pattern and stays.
- **Generic by design.** Nothing looks different per producer. Style depends
  only on an event's category and severity.
- **Words.** Plain sentences that say what happened and what to do. They never
  blame the person. The server's operator is "the host".

![s0: How new screens are decided](images/design-system/s0-how-new-screens-decided.webp)

## 2. Tokens

### 2.1 Colour

The app's theme is `ColorScheme.fromSeed(Colors.indigo)` in Material 3. It
follows the phone's light or dark mode. The design is dark first. In screens,
use roles, never raw values.

![s1: Color: dark scheme](images/design-system/s1-color-dark-scheme.webp)

| Role | Dark | Light |
| --- | --- | --- |
| primary | `#bac3ff` | `#515b92` |
| onPrimary | `#222c61` | `#ffffff` |
| primaryContainer | `#394379` | `#dee0ff` |
| onPrimaryContainer | `#dee0ff` | `#394379` |
| secondaryContainer | `#434659` | `#e0e1f9` |
| onSecondaryContainer | `#e0e1f9` | `#434659` |
| tertiary | `#e6bad7` | |
| error | `#ffb4ab` | `#ba1a1a` |
| onError | `#690005` | `#ffffff` |
| errorContainer | `#93000a` | `#ffdad6` |
| onErrorContainer | `#ffdad6` | `#93000a` |
| surface | `#121318` | `#fbf8ff` |
| surfaceContainerLowest | `#0d0e13` | |
| surfaceContainerLow | `#1b1b21` | `#f5f2fa` |
| surfaceContainer | `#1f1f25` | `#efedf4` |
| surfaceContainerHigh | `#29292f` | `#e9e7ef` |
| surfaceContainerHighest | `#34343a` | `#e4e1e9` |
| onSurface | `#e4e1e9` | `#1b1b21` |
| onSurfaceVariant | `#c7c5d0` | `#46464f` |
| outline | `#90909a` | `#767680` |
| outlineVariant | `#46464f` | `#c7c5d0` |
| inverseSurface | `#e4e1e9` | `#303036` |
| onInverseSurface | `#2f3036` | `#f2eff7` |
| inversePrimary | `#515b92` | `#bac3ff` |

The dark values and the light primary, container, surface and outline values
were read from the running app. The light `onErrorContainer`, `inverseSurface`,
`onInverseSurface` and `inversePrimary` are the standard Material 3 values for
the indigo seed. They were not read from the app. R65 checks them against the
app's theme.

What each role means:

| Meaning | Role | Where |
| --- | --- | --- |
| Critical and high severity | error | event icon, severity chip icon |
| Normal severity | primary | event icon |
| Low severity | onSurfaceVariant | event icon |
| Unread | primary dot, bold title | inbox row |
| Unread count | error badge | Inbox tab |
| Section label | primary, titleSmall | settings groups, role sections |
| Field error, a destructive confirm button | error | field border, label, help; the dialog's confirming action |
| Error banner | errorContainer and onErrorContainer | something stopped and the person can act |
| Offline, stale and notice banners (app and web) | surfaceContainerHigh and onSurface | neutral, not the person's fault |
| Snackbar | inverseSurface and onInverseSurface, action inversePrimary | a result or a failed change |

### 2.2 Type

The Material 3 scale with Roboto. Monospace (Roboto Mono) is only for opaque
values the person may copy: metadata, keys, IDs. Dates are local, to the
minute: `2026-10-10 01:19`.

| Style | Size and line | Weight | Sample |
| --- | --- | --- | --- |
| headlineSmall | 24/32 | 400 | Your action: approve the release |
| titleLarge | 22/28 | 400 | SignalHub · Settings · Devices |
| titleMedium | 16/24 | 500 | Unread event title |
| titleSmall | 14/20 | 500 | Minimum severity |
| bodyLarge | 16/24 | 400 | Push notifications are on |
| bodyMedium | 14/20 | 400 | Info · Normal · backup-jobs |
| bodySmall | 12/16 | 400 | 0/100 |
| labelLarge | 14/20 | 500 | Create pairing code |
| labelMedium | 12/16 | 500 | |
| labelSmall | 11/16 | 500 | |

![s2: Type: Material 3 scale, Roboto](images/design-system/s2-type-material-3-scale-roboto.webp)

### 2.3 Spacing and shape

| Token | Value | Used by |
| --- | --- | --- |
| Spacing | 4, 8, 12, 16, 24 | 16 is the screen edge. 24 is a list item's trailing edge. |
| Touch target | 48 dp | icon buttons, rows, switches, the bell, a snackbar's action, a dialog's buttons |
| Full radius | height / 2 | buttons, segmented buttons, switches |
| Small radius | 8 | chips |
| Other radii | 28 dialogs, 16 cards, 12 banners and key boxes, 4 snackbars | |
| Dividers | 1 dp outlineVariant | between folding groups |
| Sizes | 360 dp minimum, 412 dp drawn | Producers and the key screen are checked at 360 dp and at 200% text. Landscape keeps the layout, with content at most 600 dp wide and centred. Tablets are out of scope for R65. |
| Bottom bar and insets | 80 dp plus the system navigation inset | The floating button sits 16 dp above the bar. A list under a floating button has 88 dp of bottom padding. |
| Elevation | none | Tonal surfaces. A floating button and a menu are the only lifted things. No shadows. |

![s3: Shape and space](images/design-system/s3-shape-space.webp)

## 3. Components

### 3.1 The app's existing components

These are rebuilt from the screenshots of app 2.26.6 (1 px is 1 dp).

- **App bar of the inbox:** Filter and Mark all as read only. There is no gear.
  Settings is a tab, and the unread count is on the Inbox tab.
- **Inbox row:** a category icon coloured by severity, a bold title and a dot
  while unread, a one-line summary and the time.
- **Category icons**, the same on the app, the web page and the admin page (the
  maintainer, G8, 2026-10-25): *Action required* `pending_actions`, *Blocked*
  `block`, *Completed* `check_circle`, *Info* `info`, an unknown category `label`.
  Older images and the R81 drawing sources show the raised hand (`pan_tool`)
  for *Action required*; this line supersedes them.
- **Event details:** a headlineSmall title, outlined chips for category and
  severity, a tonal button for the link, and label and value pairs.
- **Folding settings group:** a one-line summary of its values. It stays open
  or folded as the person left it.
- **Segmented button, switch row, radio row with a preview action.**
- **Device row, destructive row, text field with counter, filled button** for a
  screen's main action.

![s4: Components, as the app draws them (1 px = 1 dp)](images/design-system/s4-components-app-draws-them-1.webp)

### 3.2 Patterns added for users

Each is built from the tokens above. None adds a colour or a type size.

- **Bottom navigation.** Inbox, Producers, Settings. An admin adds People. It is
  80 dp on surfaceContainer, with a secondaryContainer pill under the selected
  icon (filled glyph) and the unread count as an error badge on Inbox. It shows
  on the four top-level screens only. Pushed screens hide it. Its labels never
  wrap: at large text sizes their text scale is capped at about 1.3x, and the
  icons keep their size.
- **Web navigation rail.** The same destinations and pill, 88 px wide, from
  about 840 px. The logo is at the top and the account button at the bottom.
  The account button opens a menu with Devices and Sign out. Below 840 px it
  becomes the bottom bar. People is for admins only.
- **Producer row.** A neutral avatar (never per producer), the name, a
  middle-dot summary and the bell. The name takes the free width and ends in an
  ellipsis. The Yours tag, the bell and the chevron keep their size.
- **Search and filter chips.** A 56 dp search field (surfaceContainerHigh, full
  radius), then single-choice chips that scroll sideways: All, Yours,
  Subscribed, Can subscribe, Disabled (only the producers disabled by their
  owner or by the host). A selected chip is secondaryContainer with a check.
  In the app a chip row scrolls sideways and a chip never wraps. On the web
  page and on the admin page the row wraps onto a second line at narrow widths,
  so no chip (the Disabled chip above all) is ever hidden (R6, section 9.2). A
  chip's hit area is padded to 48 dp (48 px on the web).
- **Role sections.** A primary label with a count, one sentence on what the
  role can do, then the rows. The sections are Admins, Mods and Basic, in that
  order. An empty section is hidden.
- **Key shown once.** The key in monospace on surfaceContainerHigh, Copy and
  Share, one plain sentence in its own low container, a send example, and a
  full-width filled Copy and close. It is a full screen, not a dialog, with a
  48 dp Close icon at the top left. System Back and predictive back go through
  the same guard, which asks once if the key was not copied.
- **Empty state.** A 48 dp outline-coloured icon over a titleLarge (22/28)
  sentence saying what is missing, one body sentence, and at most one tonal
  button. It is centred in the space left under the search and chips. Every
  empty state uses this title size.
- **QR sign-in card (web).** A centred surfaceContainerLow card with a 24 dp
  radius. It has the steps in one sentence, the code on a light plate, and a
  waiting line with a countdown. At zero the code refreshes itself. On success
  the card shows a check and opens the inbox. On a phone-width page the QR is
  replaced by a typed code and an Open the app button.
- **Questions and answers (R81).** An answer card under an event's message, a
  read-only card, the *To answer* chip and the inbox lines, and the
  notification's *Tap to answer* line. They are built from the tokens above and
  are specified in section 10.

![s5: Patterns added for users](images/design-system/s5-patterns-added-users.webp)

### 3.3 Feedback and state components

![s6: Feedback and state components](images/design-system/s6-feedback-state-components.webp)

**Snackbar** (plain, with Retry, with Undo). One or two lines, at most one
action, gone after 6 seconds (also one with an action, never kept until it is
used). It floats 8 dp above the bottom bar. Plain says a
result. Retry follows a change that failed and went back to what it was. Undo
follows a change that can be reversed exactly. A failure the person must act on
is a banner, not a snackbar.
Tokens: inverseSurface, onInverseSurface 14/20, action inversePrimary 500,
radius 4, minimum height 48, action target 48 by 48.

**Confirmation dialog.** The title is a question that names the thing and is
never truncated. The body is one or two sentences: who is affected and whether
it can be undone. Cancel is quiet and on the left. The action is a verb in
words, in error colour only when it cannot be taken back. Never "OK" or "Yes".
It dims the screen and closes on Cancel or a tap outside, never on the
destructive action by accident.
Tokens: surfaceContainerHigh, radius 28, padding 24, title headlineSmall,
body bodyMedium onSurfaceVariant, text buttons 48 high, scrim black at 62% in
dark and 32% in light.

**Field error.** Shown under the field while the person types, on Create and
Rename alike. It says what is wrong and what to do. The 2 dp border, the label,
the help line and a trailing error icon all turn to the error colour, so it is
never colour alone. The submit button stays off (12% fill, 38% text) until the
field is valid. Exception: the answer card's *Send answer* stays enabled and
moves the focus to the error (10.1).

**Banners.** Error (errorContainer): something stopped and there is a next
step. Offline (neutral): reading still works and anything that writes is greyed.
Stale (neutral, with Try again): the refresh failed, so the older list stays
with its time. A banner sits under the app bar and search, above the list. It
is inline: it pushes the list down and never covers it.
Tokens: radius 12, minimum height 56, icon 24, action 48 high text button.

**Loading.** A list that loads shows skeleton rows with the shape of the real
row, at least three. Never a spinner for a whole list. A button that works keeps
its width and label, shows a spinner in its icon slot and ignores taps. Screens
that need a name in the title wait for it. Exception: *Send answer* reads
*Sending* while it works (10.3).

**Bell toggle.** One control per producer row for subscribing, in place. A tap
swaps the bell for a progress ring and ignores taps until the call ends. On
failure it goes back to what it was, and a snackbar with Retry says so. Offline
it is greyed. The bell stays on a disabled producer so it can be
unsubscribed. The visible circle is 40 dp inside a 48 by 48 dp target.

| State | Look |
| --- | --- |
| Subscribed | secondaryContainer and onSecondaryContainer, filled glyph |
| Not subscribed | 1 dp outline and onSurfaceVariant, outlined glyph |
| In flight | 24 dp ring (stroke 2.5) in the circle |
| Disabled or offline | 38% |

**Tags.** A role tag is a word (Admin, Mod, Basic), never an icon or a colour
alone, in a 24 dp pill: filled primaryContainer (Admin), tonal
secondaryContainer (Mod), outlined (Basic). No tag is ever red. Label tags are
20 dp with a 6 dp corner: neutral surfaceContainerHighest for Yours,
primaryContainer for You and This browser.
Device tags use the same label tags: `Admin device` (primaryContainer),
`Browser` (neutral), `This device` and `This browser` (primaryContainer),
`Revoked` (neutral, with the name set quiet). The app and the web page use
these words and no others.

**Key box and code snippet.** The key is monospace and wraps at any character,
so the whole key is always visible. A tap or long press selects all of it. Copy
turns to Copied for two seconds, except on the key screen, where Copied stays
while the screen is open. If the clipboard is refused, the key box shows the
selected state and a line says how to copy by hand. The snippet is a smaller
monospace block with a sample host and the fake sample key only.

```
curl -X POST https://signalhub.example/api/v1/events \
  -H "Authorization: Bearer shpk1_EXAMPLEKEY-not-a-real-key-0000" \
  -H "Content-Type: application/json" \
  -d '{"category":"INFO","severity":"NORMAL","title":"Hello"}'
```

**Inbox badge.** The number of unread events of the producers you subscribe to,
on the Inbox tab only. Up to 99 it shows the number. Above that it shows
`99+`. At zero it is absent. The screen reader says the real count
(`Inbox, 124 unread`). When nothing is unread and there are questions to
answer, the badge is a dot without a number, named *Inbox, N to answer*; with
both, the number is the unread count and the name is *Inbox, N unread, M to
answer*.

**Browser device row.** A browser is a device in every rule, so it uses the
device row on the app and the web page: the `language` (globe) icon, the name,
a `Browser` tag and a summary. The one in use has a `This browser` tag and no
Revoke (Sign out is in Settings). A revoked browser stays listed, quiet, with a
`Revoked` tag, until it is deleted. The summary says when the device was last
active, `Not used yet`, or `Revoked 4 Oct`. The name comes from the browser and
system (`Firefox on Linux`) and can be renamed.

**"Not available any more" screen.** Full screen after a 404 on a producer or
an event. It uses the empty-state anatomy (not an error): a plain title that
names no one, wrapped in balanced lines, one sentence on the likely reason and
one tonal button back to a list. There is no notice of losing access.

**What's new card.** Shown once at the top of the inbox on a device that was
already connected when the app updated. A newly connected device gets the
welcome instead. It lists what changed, one bold lead and one sentence each (the
People line only for an admin). It has two text buttons: a primary action that
opens the tab and dismisses, and Got it, which dismisses for good.

**Web dialog and banner.** The web page uses the same components with larger
targets (all 48 px high). A dialog is centred at 480 px and closes on Escape,
and starts with focus on Cancel. A banner is a full-width bar under the page
header. There is no snackbar with Undo on the web page or on the admin page: the page
confirms instead and shows a failed change inline. A snackbar there only says
that something happened, may carry Retry after a failure, and never covers a
control (R3, section 9.2). The key dialog is the exception. Escape and a tap on the
scrim do nothing, so the key cannot be lost by accident.

![s9: The same components on the web page](images/design-system/s9-same-components-web-page.webp)

## 4. Patterns

| Pattern | Rule |
| --- | --- |
| Navigation | A bottom bar with Inbox, Producers, Settings (People for an admin), the unread count as a badge on Inbox. Settings is a tab, so the inbox has no gear. Pushed screens hide the bar and show a back arrow. On the web page the bar is a rail beside a wide screen. |
| Folding groups | A group folds with a one-line summary of its values and stays as the person left it. |
| Destructive actions | A plain row or text button, confirmed in a dialog naming what goes. The confirming button is always a text button in the error colour, on the app and on the web. Never a red filled button. |
| Wording | Plain sentences, sentence case, no jargon. See section 5. |
| Secrets | Shown once, in monospace, with a copy action and a sentence saying it will not be shown again. The key screen offers Copy and close, and Copied stays on it. |
| Status | Said in words next to the control (`Push notifications are on`), not only by colour. |
| Roles | A role is said by a section and its one-sentence explanation, or by a tag whose form differs. The app shows what a role can do and hides what it cannot, or says who can help (`Ask an admin of this server.`). |
| Errors | A field error under the field. A failed change is a snackbar with Retry. A list that failed is a banner or an empty state with Try again. A missing thing is the full-screen "not available" state. Each says what happened and what to do. |

![s11: Patterns to keep](images/design-system/s11-patterns-keep.webp)

### 4.1 Undo or confirm

This is the app's rule. The web page and the admin page have no Undo snackbar
(R3, section 9.2): where the table says Undo, they confirm in a dialog or, for
a harmless change, make it and say so. The app is unchanged.

If an action can be reversed exactly and only the person who did it is
affected, do it at once and offer Undo in a snackbar. If it cannot be reversed,
or someone else is affected, ask first in a confirmation dialog. If it is
harmless and reversible by the same control, add nothing.

| Action | Pattern | Why |
| --- | --- | --- |
| Subscribe, unsubscribe | Snackbar with Undo (app only) | Idempotent. Stored events are hidden, not deleted. On the admin page, Unsubscribe is a confirmation: it hides all of that producer's events from the user, old ones too. |
| Enable a producer | Nothing extra | Keys work again. Nothing is lost. |
| Disable a producer | Confirm | Its senders are turned away until it is enabled. |
| Revoke a key | Confirm (error colour) | For good. The key never works again. |
| Remove someone from the list | Confirm (error colour) | Ends their subscription. Adding back does not restore it. |
| Public to Private | Confirm | Ends the subscriptions of everyone but you and the people on the list. |
| Revoke a device | Confirm (error colour) | For good. A revoked device never works again. |
| Sign out of a browser | Confirm (ordinary action) | The browser stops being a device. Signing in again is possible from the phone. |
| Change a role | Confirm (primary colour) | Someone else is affected, but a role can be changed back. |
| A change that fails | Snackbar with Retry | Nothing changed, so there is nothing to undo. |

![s8: Undo or confirm](images/design-system/s8-undo-or-confirm.webp)

## 5. Wording

The canonical strings. The app and the web page use these and no others.

- **The host.** The person who runs the server is "the host". No screen names a
  person as the server's admin. The welcome and Settings › About this server
  say: `The host runs this server and can see every event on it.`
- **Yours.** The chip and the tag on a producer you own are both `Yours`. Never
  "Mine".
- **Admin help.** When a role cannot do something: `Ask an admin of this server.`
- **Create button:** `Create`.
- **Copy:** `Copy`, then `Copied`. On the key screen `Copied` stays while the
  screen is open. Elsewhere it lasts 2 seconds.
- **Subscribe failure:** `Couldn't subscribe to NAME. Try again.` and
  `Couldn't unsubscribe from NAME. Try again.` (with Retry).
- **Unsubscribe:** `Unsubscribed from NAME. Its events leave your inbox.` (with
  Undo).
- **Sharing line on a private producer:** `Only you`, `Shared with 1 person`,
  `Shared with N people`. A public producer shows none.
- **Producer row summary:** yours `Private · 2 people · last event 00:36`,
  `Public · 2 keys · last event 01:19`, `Private · 1 key · no events yet`;
  others `Ana · Public`. The list order is Yours, then Subscribed, then Can
  subscribe, each A to Z.
- **Sign-in path:** `Settings › Sign in a browser`. Never
  `Settings › Devices › Sign in a browser`.
- **Settings order:** Push filters, Alert, Devices, Sign in a browser, About
  this server, This device.
- **Device tags:** `Browser`, `This device`, `This browser`, `Admin device`,
  `Revoked`. The browser icon is `language`.
- **Expired or used pairing code:** `This pairing code has expired or was
  already used. Ask for a new one.`
- **A removed device or person:** `This device is no longer connected to
  SignalHub. To use it again, ask for a new code, or ask the host.`
- **Sample data only.** Hosts are `signalhub.example`. The only key is
  `shpk1_EXAMPLEKEY-not-a-real-key-0000`, and key rows show
  `shpk1_EXAMPLE1…`. Pairing links have the real form
  `signalhub://pair?server=…&code=shpc1_…`, shortened with an ellipsis.
- **No gendered pronouns** in copy. Use "they" or the name.
- **The About line:** `Server: SignalHub 3.4.0 · commit a1b2c3d`, then
  `This app: …`, and on the web `This page: …`. The version is a sample.

## 6. Accessibility

![s7: Accessibility, text size and motion](images/design-system/s7-accessibility-text-size-motion.webp)

### 6.1 Accessible names for icon-only controls

| Control | Name a screen reader speaks |
| --- | --- |
| Back arrow | Back |
| Close (forms, the key screen, the scanner) | Close |
| Inbox filter | Filter events |
| Mark all as read | Mark all as read |
| People search | Search people |
| Clear search | Clear search |
| Row menu | More actions for NAME |
| Rename pencil | Rename NAME |
| x on an allow-list chip | Remove NAME |
| x on an answerer's row | Remove NAME from Who can answer |
| x on a filter chip | Remove filter NAME |
| Revoke on a key row | Revoke key shpk1_EXAMPLE… |
| Bell toggle | Subscribed to NAME. Double tap to unsubscribe. / Not subscribed to NAME. Double tap to subscribe. / Subscribing to NAME / Unsubscribing from NAME |
| Segmented button and switch | The state is spoken: "Private, selected", "Info, on" |
| The disabled Admin segment | Admin, not available. Set on the admin page |
| Inbox tab with a badge | Inbox, 3 unread |
| The camera region of the scanner | Camera, point at the invitation code |
| The sign-in QR code (web) | Sign-in QR code. To sign in without scanning, use a code instead. |
| The account button (web) | Account menu, NAME |

### 6.2 Text size and long names

- Type follows the system text size up to 200% (Flutter's text scaler). The one
  exception is the bottom bar's labels, which are capped at about 1.3x. Rows
  grow in height and never clip.
- The bar's labels never wrap. The bar grows only by the extra line height.
- A one-line name ends in an ellipsis. Its tag, the bell and the chevron keep
  their size. At 200% a row's summary wraps to two lines, and the name still
  truncates at its end.
- Sheets and bottom bars clear the system's navigation bar. Dialogs and sheets scroll. Buttons grow and their labels wrap. Keys and
  addresses wrap at any character.
- Examples: `images/producers/1n-360dp-wide-text-200.webp`,
  `images/new-producer-key/2b6-360dp-wide-text-200.webp`,
  `images/people-devices/3b2-360dp-wide-text-200.webp`.

### 6.3 Focus (web page)

- Focus follows reading order: rail, header, then the content. On the sign-in
  page, Use a code instead comes before the QR code.
- A dialog starts on Cancel and keeps focus inside until it closes. Escape
  closes a dialog or a menu and returns focus to the control that opened it.
- Every control has a visible focus ring: 2 px primary, 2 px offset, never
  removed.

### 6.4 Motion

| What | Motion |
| --- | --- |
| Pressed, hover, focus | Material 3 state layers at 8%, 8% and 10%. A ripple on touch. No scale. |
| Bell change | 100 ms cross-fade between the bell and the progress ring |
| Snackbar | In over 200 ms (emphasized decelerate), out over 150 ms |
| Dialog | Fade and scale from 0.9 to 1 over 200 ms, out over 100 ms |
| Copy to Copied | 120 ms cross-fade, the button's width held |
| Skeleton shimmer | 1.2 s, linear |
| QR refresh | 150 ms cross-fade |
| Tab switches and list filtering | No animation. They are used constantly. |
| Send answer to Sending | The label and the ring cross-fade over 100 ms, as the bell; the ring stops turning for reduced motion |
| The card to its result, the *Other* field, the closes-soon line | No animation: the result replaces the card at once (10.3), the field appears with the focus, the minutes change in place |
| Reduced motion | No slide and no scale: opacity only. The shimmer is static. The progress ring stays and does not turn. |

## 7. Contrast

Computed from the hex values. Text needs 4.5:1. Icons, borders and large text
need 3:1. Every pair passes. A skeleton row is a placeholder and is exempt, as
is a disabled control.

| Pair | Dark | Light |
| --- | --- | --- |
| Error text and field border on surface | 10.9 (`#ffb4ab` on `#121318`) | 6.1 (`#ba1a1a` on `#fbf8ff`) |
| Error text on the dialog (surfaceContainerHigh) | 8.5 (`#ffb4ab` on `#29292f`) | 5.3 (`#ba1a1a` on `#e9e7ef`) |
| Error banner: onErrorContainer on errorContainer | 7.2 (`#ffdad6` on `#93000a`) | 7.2 (`#93000a` on `#ffdad6`) |
| Neutral banner text, icon | 11.2, 8.5 | 14.0, 7.6 |
| Snackbar text, action | 10.2, 5.0 | 11.5, 7.7 |
| Error badge: onError on error | 7.7 (`#690005` on `#ffb4ab`) | 6.5 (`#ffffff` on `#ba1a1a`) |
| Role tags: Admin, Mod, Basic text | 7.2, 7.2, 10.9 | 7.2, 7.2, 8.9 |
| Basic tag outline, bell outline, empty-state icon (need 3) | 5.9 (`#90909a` on `#121318`) | 4.3 (`#767680` on `#fbf8ff`) |
| Label tag (Yours) on surfaceContainerHighest | 7.3 | 7.2 |
| Primary text on surface, on the dialog | 10.9, 8.5 | 6.1, 5.3 |
| What's new text | 7.2, 7.2 | 7.2, 7.2 |

![s10: Contrast, checked](images/design-system/s10-contrast-checked.webp)

The light theme is drawn for the key screens, the dialogs, the banners and the
web sign-in and Settings. See `images/light-theme/`: [5a](images/light-theme/5a-inbox.webp), [5b](images/light-theme/5b-producers-search-chips.webp), [5c](images/light-theme/5c-key-shown-once-full-screen.webp), [5d](images/light-theme/5d-people-3b-sections-by-role.webp), [5e](images/light-theme/5e-producers-row-each-state.webp), [5f](images/light-theme/5f-confirmation-dialog-revoke-key.webp), [5g](images/light-theme/5g-snackbar-change-failed-retry.webp), [5h](images/light-theme/5h-offline-banner-older-list.webp), [5i](images/light-theme/5i-error-banner-disabled-by-host.webp), [6a-l](images/light-theme/6a-l-sign-desktop-browser.webp), [6d-l](images/light-theme/6d-l-sign-phones-own-browser.webp), [8a-l](images/light-theme/8a-l-settings-desktop-this-browser-devices.webp), [8c-l](images/light-theme/8c-l-revoke-browser-confirmation-web-page.webp), [6f-l](images/light-theme/6f-l-web-banner-sign-ended-offline.webp).

## 8. R64's rules and how they were applied

### 8.1 Skill roles

All the design skills were kept. Each was used only for its role, one at a time,
so they never contradict.

| Role | Skill | How it was used |
| --- | --- | --- |
| Direction and critique | `impeccable`, *Operate* mode, with its Android reference | Refined the incumbent look. Its critique and audit reviewed the screens. It never started a new visual world. Its hooks stayed off. |
| Reference data and checklists | `ui-ux-pro-max` | Patterns and UX rules (its Flutter stack for the app, only its general UX and style domains for the web page) and its pre-delivery checklist. It did not write its own `MASTER.md`. This file is the only design system file. |
| Polish and motion | `emil-design-eng` | Timing, easing and interruptible feedback. In the app its principles are carried to Flutter's animations, not its CSS. |
| Generic-look checks | `frontend-design`, `design-taste-frontend` | Lists of tells to check the screens against. Never used to choose a new look. |
| Code audit (in R65 and R66) | `web-design-guidelines`, `playwright-cli`, `impeccable`'s audit | Not part of R64. |
| Not used | `ui-ux-pro-max`'s `design`, `ui-styling`, `design-system`, `brand`, `banner-design`, `slides` | Outside services, Tailwind or slides. They do not fit SignalHub. |

### 8.2 Settled disagreements

- Touch targets are 48 dp (Material), not 44 pt.
- The app keeps the Material type scale with Roboto. A brand face would only come
  through the theme.
- SignalHub's middle-dot summaries (`Info · Normal · producer`) are its own
  established pattern and stay, although `frontend-design` lists such strings
  as a generic tell.
- Product screens favour restraint (one expressive element at most) over
  `impeccable`'s "go all out" and taste's motion showcases.

### 8.3 Truth over wish

The designs show only what the server provides. Where a design wanted data the
server does not give, the design changed. The cuts are listed in
[WALKTHROUGH.md](WALKTHROUGH.md#what-was-left-out).

## 9. The admin page (R73)

R73 drew the operator's admin page (`/admin/`, served on the backend's own
port) and the web page's New producer action. The operator is the host, signed
in with the admin token (no accounts, no passwords). The drawings, the flows
and the server changes they need are in [../admin/](../admin/README.md). The
sources are in `source/`: the `Admin - ...` pages and the five `admin-*.css`
stylesheets. The page uses the tokens, the type scale, the shapes and the words
of the sections above. It adds the components in 9.3 and follows the rules in
9.2.

![s12: The Admin page section of the design system page](../admin/images/design-system-admin/s12-admin-page.webp)

### 9.1 Layout

- **Desktop first.** At 1440 px: an 88 px navigation rail, a list that takes the
  rest, and a 480 px detail pane. Forms are dialogs or panes, never a form
  under a list.
- **Below 1180 px** the pane becomes a side sheet, 560 px from the right edge.
- **At 390 px** the rail is a bottom bar of the five destinations, a table is
  two-line rows, a detail is a full screen with a back arrow, and a dialog is a
  full-width sheet or screen. No sideways scroll.
- **Five destinations:** Devices, Users, Producers, Events, Status. At the foot
  of the rail: the status button and the account avatar (its menu holds the
  version and Sign out).
- **Sign-in** is the only screen without the rail: one field for the admin
  token, kept in the page's memory only.

### 9.2 Rules every admin page follows (R1 to R8)

| Rule | Text |
| --- | --- |
| R1 | **Dialog actions are text buttons**, 48 px high. The confirming action is in primary. A destructive confirming action is in the error colour. Never a filled red button. Form dialogs follow the same rule (Create, Rename, Invite, Send a test event). |
| R2 | **Header actions are tonal buttons** (New producer, Connect a device, Invite a user, Send a test event), on the admin page and on the web page. Filled is for the one primary action of a form. |
| R3 | **Snackbars never cover a control, and carry no Undo.** On the admin page a snackbar sits at the bottom left of the list area, above the pager and the pane's foot, so both stay reachable. It goes after 8 seconds or on Dismiss. The page confirms instead of offering Undo. Retry is allowed after a failure. This replaces the Undo snackbar of 4.1 on the web page and the admin page. |
| R4 | **Every control is 48 px high** (pager, bulk bar buttons, a row's checkbox hit area, a chip's remove x, the snackbar action, the token toggle). The visible shape may be smaller (an 18 px box, a 32 px chip). The target is not. |
| R5 | **Canonical wording** (the table in 9.4). |
| R6 | **Chip rows wrap** onto a second line on the web page and the admin page, so no chip is hidden. This replaces "Chips never wrap" for those two. The app's chips still scroll sideways. |
| R7 | **Neutral pronouns.** A person is their name or "they". |
| R8 | **No sort arrows.** The API has no sort. Events say "Newest first". The other lists are ordered by the page, and the page's note says so. |

### 9.3 Components the admin page adds

- **Rail and status button.** Five destinations with a secondary-container
  pill under the selected one. The status button reads `/api/v1/admin/status`
  and `/q/health` every 30 seconds. Each of its four states differs by icon and
  word, never by colour alone: Working (server icon, primary dot), Check (warning
  icon, the word in error), Checking (outline dot) and Unknown (question mark).
  Pressing it opens Status.
- **Table row.** 56 px. The name in on-surface, then plain cells in
  on-surface-variant. A selected row is a secondary container with a 16 px
  radius. States are always a word or a tag as well as colour: Disabled (an
  outlined tag, its keys not working), Quiet (a plain tag: no event for a
  week), Revoked (dimmed, with its tag, text kept at 4.5 : 1 in both themes) and
  an unread event with the Push problems marker (an error outline, an icon and
  words).
- **Detail pane and side sheet.** A 22 px title with a close button, tabs only
  when the thing has them (Event, Pushes), a scrolling body, and a foot with the
  actions of the whole thing. The side sheet is the same content, 560 px, over a
  32% scrim, closed by its button, Escape or the scrim.
- **Bulk bar.** Under the filter chips, 56 px, secondary container: the count
  and the actions that apply to every selected row. Clear selection is the first
  action. Delete is an error text button and opens a confirmation naming the
  count.
- **Filter chip and its menu.** One 32 px outlined chip per filter. A chip with
  a choice is secondary container with a check and its value. Producer, Category
  and Severity take several values (a menu of checkboxes that stays open).
  Read state and Push problems are single choice or on and off. Received opens a
  panel with a from and a before date and presets. A chosen filter is also in
  the address.
- **Technical details fold.** Closed by default. Raw ids, check names and values
  in monospace, with a Copy action. Nothing in it is secret.
- **Status row.** A part, its value, one line on what to do, and a chip with an
  icon and a word (Working, Needs attention, Look, Could not read). A problem row
  has an error edge and tint and moves to the top under its own heading.
- **Sign-in card.** One field for the token (32 characters at least, a 48 px
  show toggle) and one button.
- **Pager.** Newer and Older, since the list is cursor based (25 a page).
- **Dashed note.** In the drawings only: "Needs a server change" marks a detail
  the server cannot give today.

### 9.4 Wording (R5)

| Use | Where | Meaning |
| --- | --- | --- |
| Create | In a create dialog | Never "Create producer". |
| Could not | "Could not save the name" | Never a contraction. |
| Send a test event | Everywhere, the same words | An event sent as an existing producer. |
| Revoke | A device, a browser, a key or a user | Stops working and stays listed. |
| Delete | Only revoked devices, and events | Gone for good. |
| Disable, Enable | A producer | Its keys stop or start working. Its events stay. |
| Remove | One entry out of a list (an allowed user) | Ends that person's subscription. |
| Unsubscribe | A subscription | That producer's events are hidden, old ones too. |
| People | Their name or "they" | No he or she. |

A change made on the admin page (revoke, rename, delete) sends no push. Only
changes made from a device, pairings and browser sign-ins do.

### 9.5 Status: when SignalHub "needs attention"

The first line of Status answers in words and an icon. These are the rules
the owner approved at the design gate (G6, 2026-10-11): the database is down; no
push service is set up; every device that has a push address failed its last
push (at least one such device), so the push service is likely down; the events
waiting to be pushed are above 20 and not falling over two checks; retries were
given up since the page was opened (page memory, not since the server started);
or a part could not be read. One device's failure is a row warning ("2 devices'
last push failed") with a link to Devices filtered to Push problems, never the
headline.

### 9.6 Light theme

The admin drawings are dark first. `admin-events.css` holds both token sets: the
dark `:root`, and a `.light` set that is the users' light roles (primary
`#515b92`, secondary container `#e0e1f9`, surface `#fbf8ff`, surface container
low `#f5f2fa`, error `#ba1a1a`). A `light` class on a frame switches it in the
drawings. The built page switches the same tokens with `prefers-color-scheme`,
as `admin.css` and `app.css` do. No colour is written out in a rule: the error
row tint, the disabled and busy buttons, the scrim, the shadows and the browser
frame are all tokens. Light frames: `../admin/images/light-theme/`. Contrast of
the light set, from the token values: the lowest text pair is primary on surface
container highest (4.98 : 1), error on the dialog is 5.27 and the note on the
canvas 5.30. The lowest non-text part is the outline on surface container
highest or on an error container (3.48 : 1, needs 3). In light a revoked row's
text is on-surface-variant, not outline (outline was 4.06 : 1).

### 9.7 Motion

Short and quiet: this is a tool for operating. Entering things ease out so they
answer at once. Leaving things are faster than entering. Nothing starts from
scale 0. Only opacity and transform change. Everything is interruptible.

| What | Enter | Leave | Easing |
| --- | --- | --- | --- |
| Detail pane (1180 px and wider) | 200 ms: slides 24 px from the right and fades in | 150 ms fade | `cubic-bezier(.05,.7,.1,1)` (emphasized decelerate) |
| Side sheet (below 1180 px) | 250 ms from the right edge, the scrim fades in over the same 250 ms | 150 ms, then the scrim | decelerate in, `cubic-bezier(.3,0,.8,.15)` out |
| Dialog | 200 ms: fades and scales from 0.9 to 1 around its centre | 100 ms fade | decelerate in, accelerate out |
| Filter menu and date panel | 100 ms: fades and scales from 0.95, from its chip | 80 ms fade | decelerate |
| Bulk bar | 150 ms cross-fade with the space it takes (the table does not jump) | 100 ms | decelerate |
| Snackbar | 200 ms: fades and rises 8 px | 150 ms fade, after 8 s or on Dismiss | decelerate |
| Row selected, tab changed, Technical details folded | No animation | None | None |
| Loading bar and the sign-in spinner | Looping | None | linear |
| Reduced motion | No slide and no scale: opacity only, 100 ms at most | Opacity only | linear |

### 9.8 The web page's New producer action

On the users' web page the floating New producer button sat on top of the last
producer. The owner chose **option A**: a tonal New producer button in the
list header (R2), nothing floating, the first tab stop of the list. B (the
floating button kept, with space reserved under the last row) and C (a card at
the end of the list) stay drawn for the record. Chips wrap on that page (R6),
and a Disabled chip is added, so the disabled producers at the bottom are never
hidden. Frames: [web-new-producer](../admin/README.md#the-web-pages-new-producer-action).


## 10. Questions and answers (R81)

R81 drew how a producer asks a question in an event (up to 10 choices, one or
several, an optional or required typed note, an optional closing time) and how
people answer it: in the app, from the Android notification, on the users' web
page and, read-only, on the admin page. The drawings, the flows and the API they
assume are in [../answers/](../answers/README.md). The sources are in `source/`:
`App - Answering an event`, `App - Notification actions`,
`Web - Answering an event`, `Admin - Questions and answers` and
`admin-answers.css`. The words are the ones of the sections above plus the ones
below. No new colour, type size or shape is added. The owner chose **option A**
for answering (2026-10-16); B and C stay drawn for the record, in
[../answers/README.md](../answers/README.md#not-chosen).

A **producer asks**, a **person answers**. Only the producer's owner and the
people the owner named as answerers may answer, and the first answer wins. The
operator (the admin token) never answers.

Changed at G8 (2026-10-25): the sizes, the *Other* row, the producer's close and
Ctrl+Enter below supersede any frame that shows the older limits or lacks them.

### 10.1 The answer card (option A)

![1a: Option A: an answer card under the message](../answers/images/app-answering/1a-option-a-an-answer-card-under.webp)

The card sits under the message and above *Open link*, and is the same on the
app, on the web page and at phone width. The result states of 10.3 take its
place, so a state never moves.

- **Container.** surfaceContainerLow, 16 dp radius, 16 dp padding, 4 dp between
  its parts. The web card is the same at 48 px targets.
- **Heading.** *Your answer*, titleMedium (16/24, weight 500).
- **Rule line.** onSurfaceVariant body text. *Pick one.* or *Pick one or more.*
  or, for a typed-only question, *Type your answer.* Then
  *It goes to PRODUCER and can't be changed once sent.* PRODUCER is the name of
  the producer.
- **Choices**, in the order the producer sent them. A single choice is a group of
  radios, a multiple choice is checkboxes (needs at least 2 choices). Each choice
  is one 48 dp row; the whole row is the target, not the 20 dp control. The
  label is bodyLarge (16/24), at most 100 characters, and wraps to a second line
  rather than being cut.
- **Descriptions.** A choice may have a description of at most 1000 characters.
  It is shown under the label in bodyMedium (14/20) onSurfaceVariant, wraps, and
  is never cut or ellipsised. A choice without one is one line, with no gap
  where it would be. A description is plain text, never a link or markup, and it
  is never in the notification. [2p](../answers/images/app-answering/2p-a-choice-with-a-long-description.webp), [2q](../answers/images/app-answering/2q-multiple-choice-with-descriptions.webp)
- **Note.** An outlined field, *Note (optional)*, with the placeholder
  *Add a note for PRODUCER* and a counter *0 / 3000*. For a choice question it
  is a text area that starts at one line and grows to 4 lines, then scrolls;
  Enter adds a line. When the question has no
  choices the field is required: its label is *Your answer*, the placeholder is
  empty, and it is a text area that grows to 6 lines and then scrolls. A question
  that does not take text has no field.
- **Other row** (`textStyle: OTHER`). Instead of the note, the last row of the
  choices is *Other*, with the field *Your answer* under it once it is picked
  (counter *0 / 3000*). A single choice picks a choice or *Other*; a multiple
  choice may tick *Other* with the choices. The producer chooses the style per
  question.
- **Send answer.** A filled button. Full width on the app and at phone width; at
  its own width, left-aligned, on the web page's desktop layout. **Select then send is the
  confirmation** of 4.1: an answer goes to a producer and cannot be taken back,
  so choosing sends nothing and the button is the one deliberate step. There is
  no extra dialog and no Undo. It stays enabled; pressed with an error it moves
  the focus and says why (10.3).
- **Seven choices** make the card taller and the screen scrolls; *Send answer* is
  the last thing in the card. [2a](../answers/images/app-answering/2a-seven-choices-single-choice.webp)

### 10.2 The read-only card

![1h: Open, but you may not answer](../answers/images/web-answering/1h-open-but-you-may-not-answer.webp)

A person who is not the owner and not an answerer sees an open question as a
list, in the same place as the answer card.

- **Title.** A lock icon and who can answer, built from `ask.whoCanAnswer`, the
  owner first: one person *Rodrigo answers this*, two *Rodrigo or Ana can
  answer*, three or more *Rodrigo, Ana or Rui can answer*. Never "an admin" or
  "the operator". When nobody can answer (the owner was revoked and nobody else
  is named), the title is *Nobody can answer this now*; the line under it stays.
- **Line under it.** *You can read the question.*
- **The choices** as a disabled list in the answer card's layout: a flat
  `remove` glyph where the radio would be, the label, and the description under
  it when there is one. No radio, no checkbox, no button, no field and nothing
  that looks pressable. Nothing here takes focus. With an *Other* row, *Other*
  is the last row, with no description.
- The app's frame is [2h](../answers/images/app-answering/2h-open-but-you-may-not-answer.webp), the web page's is [1h](../answers/images/web-answering/1h-open-but-you-may-not-answer.webp). A `403` on
  *Send answer* re-reads the event and turns the card into this one, with the
  extra line *Your answer wasn't sent. You can no longer answer this question.*
  ([1p](../answers/images/web-answering/1p-a-403-on-send-the-page.webp)).

### 10.3 The states and their exact copy

One card, one place. The words are the same in the app, on the web page and in
the inbox. Curly quotes and the middle dot as separator, as in section 5.

| State | Words | Notes and frames |
| --- | --- | --- |
| Open, may answer | *Your answer*, *Pick one.* / *Pick one or more.* / *Type your answer.*, *Send answer* | 10.1. [1a](../answers/images/app-answering/1a-option-a-an-answer-card-under.webp), [1a](../answers/images/web-answering/1a-the-question-a-single-choice-with.webp) |
| Closes at | *Closes at 09:00*, grey; in the last hour *Closes at 09:00 · in 12 min* in the error colour with a clock icon. On another day *Closes 17 Oct at 09:00*. No closing time shows no line. | The words carry the urgency, so colour is not the only signal. The web page updates the minutes once a minute and does not announce them. [2j](../answers/images/app-answering/2j-it-closes-soon.webp), [1k](../answers/images/web-answering/1k-it-closes-soon.webp) |
| Sending | The choices and the note dim, the button shows a progress ring and reads *Sending* (announced *Sending answer*) | Cannot be pressed twice. Leaving does not cancel the send. The ring stops turning for reduced motion and stays visible. [2d](../answers/images/app-answering/2d-sending.webp), [1d](../answers/images/web-answering/1d-sending.webp) |
| You answered | *You answered · Merge · 19:02*, then *Note: After lunch* when a note was sent, then *Sent to ci-pipeline.* | Several choices read *You answered · Unit tests, Lint · 19:02*. A typed-only answer reads *You answered · ‘after lunch’*, then *19:02 · Sent to ci-pipeline.*; past about 40 characters the title says *You answered* and the text follows in full. A long label wraps in the title, never cut; the time stays at the end of the last line. The 40-character rule applies to a typed answer only. [2e](../answers/images/app-answering/2e-answered-by-you.webp), [2e2](../answers/images/app-answering/2e2-a-typed-question-answered.webp), [1e](../answers/images/web-answering/1e-you-answered.webp), [1q](../answers/images/web-answering/1q-you-answered-a-typed-question.webp) |
| Someone else answered | *Ana answered · Hold · 18:55*, then *Sent to ci-pipeline. Nobody else can answer now.* | The name stored with the answer, even if Ana is renamed. The icon is grey, not primary. A long label wraps, as in *You answered*. A typed answer: *Ana answered · ‘after lunch’*, then *18:55 · Sent to ci-pipeline. Nobody else can answer now.* [2f](../answers/images/app-answering/2f-answered-by-someone-else.webp), [1f](../answers/images/web-answering/1f-someone-else-answered.webp) |
| Answered first | *Ana answered first: Hold*, then *18:55. Your answer wasn't sent, and ci-pipeline has Ana's.* | The `409` carries the winner, so the card swaps at once. No error colour, no retry, the choice and the note dropped. The same person on another device with a different answer reads *You already answered: Merge. Your new answer wasn't sent.* [2l](../answers/images/app-answering/2l-someone-answered-first-while-you-were.webp), [1j](../answers/images/web-answering/1j-someone-answered-first.webp) |
| You answered with *Other* | *You answered · Other · 19:02*, then *Other: 9000, behind the proxy*, then *Sent to ci-pipeline.* Several choices: *You answered · Unit tests, Other · 19:02*, then *Other: …* | The text wraps and is never cut. Someone else's: *Ana answered · Other · 18:55*, then *Other: …*, then *Sent to ci-pipeline. Nobody else can answer now.* |
| *Other* picked, field empty | *Type your answer for Other.* under the field, with the error icon; the counter stays *0 / 3000* | On *Send answer* (and Ctrl+Enter on the web page). Focus moves to the field. |
| Leaving *Other* | Picking another choice (single choice) or unticking *Other* (multiple) hides the field and keeps its text while the event is open; picking *Other* again shows it. Only a visible field is sent. | No animation; the focus move is the feedback. |
| Closed | *Closed · nobody answered in time*, then *It closed on 17 Oct at 09:00. ci-pipeline got no answer.* | A clock icon, no warning colour. Seen by everyone, including people who may not answer. [2g](../answers/images/app-answering/2g-closed-with-no-answer.webp), [1g](../answers/images/web-answering/1g-closed-with-no-answer.webp) |
| Closed while choosing | *Closed while you were choosing · nobody can answer it now*, then *Your answer wasn't sent. ci-pipeline got no answer.* (closed by its time) or *Your answer wasn't sent. ci-pipeline closed this question.* (closed by the producer) | The `409` closed. [2l2](../answers/images/app-answering/2l2-it-closed-while-you-were-choosing.webp) |
| Closed by the producer | *Closed by ci-pipeline · Answered in the session* (without the part after the dot when no note was sent), then *ci-pipeline closed this question on 17 Oct at 08:41.* | The producer answered elsewhere and closed it (`closedBy: PRODUCER`, the time from `closedAt`). Seen by everyone; no warning colour; notifications removed. On the admin page as on the app and web page. Past about 40 characters the title says *Closed by ci-pipeline* and the note follows in full on its own line, in curly quotes. It is never cut. The icon is a grey `lock`, not the clock of a time-out (10.4). |
| Read-only | 10.2 | [2h](../answers/images/app-answering/2h-open-but-you-may-not-answer.webp), [1h](../answers/images/web-answering/1h-open-but-you-may-not-answer.webp) |
| Send failed | A snackbar *Answer not sent* with *Retry* | The failed-change pattern of 4. The choice and the note are kept as typed. Retry and the button do the same. Offline before the tap has no frame of its own: the offline banner covers it. [2k](../answers/images/app-answering/2k-send-failed-offline-or-server-error.webp), [1i](../answers/images/web-answering/1i-send-failed.webp) |
| Nothing picked | *Pick an answer to send.* / *Pick at least one answer.* / *Type an answer to send.* | Under the list with an icon. Focus moves to the first choice (to the field for a typed question or an empty *Other*), and the message is that group's or field's accessible description (`aria-describedby`, with `aria-invalid="true"`), so it is read once, with the focus. No `role="alert"`: with the focus move it would be read twice. [2o](../answers/images/app-answering/2o-field-error-nothing-picked.webp), [1m](../answers/images/web-answering/1m-field-error-nothing-picked.webp) |
| Text too long | *Too long: 43 characters over the limit.* with the counter *3043 / 3000* | Shown as soon as the text passes 3000, in the error colour. The text is never cut, and *Send answer* stays pressable and only moves the focus. [2n](../answers/images/app-answering/2n-field-error-the-text-is-too.webp), [1l](../answers/images/web-answering/1l-field-error-the-text-is-too.webp) |
| Event deleted | *This event isn't in your inbox any more* | The existing state; the answer went with the event. [2m](../answers/images/app-answering/2m-the-event-was-deleted-meanwhile.webp) |
| Owner unsubscribed | On the producer's page, under the *Subscribed* switch: *Stay subscribed to answer. While you're unsubscribed, NAME's questions don't reach you, and you can't answer them.* | Shown only to the owner or an answerer who is unsubscribed. An unsubscribed owner cannot open the event, so this page is the only place. [2i](../answers/images/app-answering/2i-you-own-the-producer-but-unsubscribed.webp), [4f](../answers/images/web-answering/4f-your-producer-unsubscribed-stay-subscribed-to.webp) |

The card's result is announced once, in a polite live region. Sending turns
into the result without animation.

### 10.4 The inbox: lines, chips and refresh

![3a: Inbox: a question to answer, waiting, answered, closed](../answers/images/app-answering/3a-inbox-a-question-to-answer-waiting.webp)

A row of a question adds one line under the usual meta line, in words, so the
state is never only an icon or a colour. The unread dot stays read state only.

| Line | Who sees it | Look |
| --- | --- | --- |
| *To answer* (with *· Closes 09:00* when there is a closing time) | An open question this person may answer now | primary, 14/20, weight 500, `question_answer` |
| *Waiting for Rodrigo* / *Waiting for Rodrigo or Ana* / *Waiting for Rodrigo, Ana or Rui* | An open question this person may only read | grey, hourglass. The names are `whoCanAnswer`, the owner first. *Waiting · nobody can answer* when nobody can. |
| *You answered · Merge*, *Ana answered · Hold* | An answered question | grey, check. One line: a long label ends with an ellipsis, the only place a label is cut; the accessible name has it in full. An *Other* answer reads *You answered · Other*. |
| *Closed · nobody answered* | A question that closed by its time | grey, `lock_clock` |
| *Closed by ci-pipeline* | A question the producer closed | grey, `lock`. The note is not in the row. |

- **Chips.** R81 adds a chip row above the list, app and web page: *Unread* and
  *To answer*. They are the only chips of the inbox. *Unread* is the same switch
  as the unread-only option of the Filter sheet, which keeps it, and producer,
  category and severity. *To answer* carries the number of open questions this
  person may answer (accessible name *To answer, 2*). The chip row is hidden
  while the inbox has no events at all and no filter is on, so the empty inbox
  (*No events yet*, `App - First run` 4c) is unchanged.
- **The chip rule.** *To answer* is shown only while its count is above 0 or
  while it is switched on. A person who never gets questions never sees it. With
  it on and nothing left, the list shows *Nothing to answer* with a button
  *Show all events*, which switches the chip off. A selected chip is
  secondaryContainer with a check, as in 3.2. On the web page the row wraps (R6).
  In the app the chip shows its own state: the app bar's Filter icon stays
  outlined for it (it fills for what the Filter sheet holds), and *Mark all as
  read* stays in the bar, off, also with nothing left (3b, 3c).
  [3b](../answers/images/app-answering/3b-the-to-answer-filter-on.webp), [3c](../answers/images/app-answering/3c-the-to-answer-filter-nothing-left.webp), [2a](../answers/images/web-answering/2a-inbox-a-question-to-answer-answered.webp), [2b](../answers/images/web-answering/2b-the-to-answer-chip-on.webp), [2c](../answers/images/web-answering/2c-the-to-answer-chip-on-nothing.webp)
- **Read state and the question are separate.** Opening a question marks it read,
  and it stays in *To answer* until it is answered or closed. *Mark all as read*
  marks it read like any event and does not remove it from *To answer*.
- **Refresh.** The web page re-reads an open event when its tab regains focus
  and after any `409`. The app re-reads it on resume. A first load always shows
  the current state. A question leaves *To answer* on the next re-read after it
  is answered or closes.

### 10.5 The notification

![1a: A question you may answer](../answers/images/notification/1a-a-question-you-may-answer.webp)

Notifications carry **no action buttons** (the owner, 2026-10-16). They stay what
Android builds from the push: title and message. For a person who may answer, the
server adds one first line to the text, and the shortened message follows after
a line break. A collapsed card (heads-up, lock screen, a collapsed shade) shows
the title and this line, so it says it is a question whatever the title; an
expanded card shows the line, then the message.

| Question | First line |
| --- | --- |
| Up to 3 single choices | *Tap to answer · Merge or Hold*, or *Tap to answer · Restart, Wait or Ignore* |
| More than 3 choices | *Tap to answer · 7 choices* |
| Multiple choice | *Tap to answer · pick one or more* |
| Typed question | *Tap to answer* |
| The labels would make the line pass 80 characters | *Tap to answer · 3 choices* |
| A person who may not answer | The event's usual text, unchanged |

The line is plain text and never shows a description. The stored message is
untouched. Tapping the notification opens the event at its top, as any event
opens; the answer card is under the message. A
critical question keeps today's alert and carries the same line ([1f](../answers/images/notification/1f-a-critical-question.webp)).

**Removal.** When a question is answered, closed or deleted, its notification
is **removed**, not replaced (the owner, 2026-10-16). A data-only notice makes
the app remove the card by its tag; nothing pops up, sounds or replaces it. The
outcome is in the inbox and the event. It goes to every device the question
reached, the answerer's other devices included, and not the one that answered.
[1d](../answers/images/notification/1d-answered-the-notification-goes.webp), [1e](../answers/images/notification/1e-closed-the-notification-goes.webp), [1e2](../answers/images/notification/1e2-deleted-the-notification-goes.webp). A phone that is offline, dozing (the
notices go at normal priority) or has the app force-stopped keeps the card until the notice arrives, and a tap then opens
the event in its current state. A swiped-away card has nothing to remove.

**With the app open.** A question that arrives while the app is in the
foreground shows in the inbox, which re-reads itself, and plays SignalHub's
alert (R57); Android shows no notification in the shade. That is Firebase's
foreground behaviour and intended (the maintainer, 2026-10-30): the person is
already looking at the inbox.

### 10.6 Who can answer: the answerers setting

![4a: Your producer: Who can answer, one person added](../answers/images/app-answering/4a-your-producer-who-can-answer-one.webp)

The owner's own producer page gets a *Who can answer* section under *Who can see
it* and the people it is shared with, above *Keys*. It is shown to the owner
only.

- **Rows.** The owner is the first row, *Rodrigo (you)*, with the second line
  *Owner · can always answer* and no control. Each added person's row says
  *Can answer its questions* and has a 48 dp close button, accessible name
  *Remove Ana from Who can answer* (the allow-list chip on the same screen is
  *Remove Ana*). The last row is *Add people who can answer*.
- **Nobody added.** *Only you can answer this producer's questions.* under the
  owner's row. [4b](../answers/images/app-answering/4b-nobody-added-yet.webp)
- **The picker** is the one of sharing: titled *Add people who can answer*,
  checkbox rows with the names of people who can see the producer and are not
  answerers yet, *Add* off until one is checked; with nobody left, *Everyone who
  can see NAME can already answer.* On the web it is a 480 px dialog with the
  focus on the first checkbox. It only adds: removing is the row's close button,
  confirmed. It says
  *They also need to be subscribed to get its questions.*, because the owner does
  not see subscriptions. Nobody else can see it: *Nobody else can see NAME. Add
  people under Who can see it first.* [4c](../answers/images/app-answering/4c-add-people-who-can-answer.webp), [4c](../answers/images/web-answering/4c-add-people-who-can-answer-the.webp)
- **Removing** is a confirmation, not an Undo (4.1), because it changes what
  someone else can do: *Remove Ana?*, *Ana won't be able to answer NAME's
  questions any more. Answers Ana already gave stay as they are.* Text buttons,
  *Remove* in the error colour; on the web the focus starts on *Cancel*. A
  failure says *Not removed* with *Retry*. [4d](../answers/images/app-answering/4d-removing-a-person-the-confirmation.webp), [4d](../answers/images/web-answering/4d-removing-a-person-the-confirmation.webp)
- A person removed from *Who can see it*, or revoked, leaves the list in the same
  moment. [4a](../answers/images/web-answering/4a-your-producer-who-can-answer-one.webp), [4e](../answers/images/web-answering/4e-your-producer-at-phone-width-one.webp)

### 10.7 The admin page

![Q1b: Answered in the app, with a note](../answers/images/admin/q1b-answered-in-the-app-with-a.webp)

The operator never answers, so nothing on the admin page is a control for
answering, and the page never says *To answer*.

- **The question block** sits in the event pane under the message and link, above
  *Producer*. It repeats the question as text: *Pick* (*One*, *One or more* or
  *No choices, typed answer*), *Note* (*Not allowed*, *Allowed, optional* or
  *Required*; *Other row, optional* for an *Other* row), *Closes* (the time,
  or *Never*), then each choice with its description. The state is a word and an
  icon: *Waiting for an answer · closes 09:00 · Rodrigo or Ana can answer* (or
  *Waiting for an answer · closes 09:00 · nobody can answer it now*), *Answered
  · Nobody else can answer now.* or *Closed · nobody answered in time*. [Q1](../answers/images/admin/q1-open-waiting-for-an-answer.webp)
- **The answer** shows who (the name stored with the answer), when and where in
  words (*in the app*, *on the web page*), what was chosen, and the note in its own
  box as text, titled *Note from NAME*. A typed-only answer's box is titled
  *Answer typed by NAME*, and an *Other* answer's *Other typed by NAME*.
  Choices are drawn as the read-only list of 10.2; a picked one has a `check`
  and the word *Picked*. The note box wraps long words and grows with its text;
  the pane scrolls. A revoked answerer keeps the name with a *Revoked* tag. [Q1b](../answers/images/admin/q1b-answered-in-the-app-with-a.webp), [Q1c](../answers/images/admin/q1c-several-choices-answered-on-the-web.webp),
  [Q1d](../answers/images/admin/q1d-a-typed-question-answered.webp), [Q1e](../answers/images/admin/q1e-closed-with-no-answer.webp), [Q1f](../answers/images/admin/q1f-the-answerer-was-revoked-later.webp)
- **List markers.** One word with an icon under the title of an event that asks:
  *Waiting* (tonal tag, hourglass), *Answered* (outlined tag, check) and *Closed*
  (plain tag, `lock_clock` when it closed by its time, `lock` when its producer
  closed it). The accessible name ends with it (*Merge R82 into main?,
  waiting*). On a phone the marker joins the second line. [L1](../answers/images/admin/l1-the-list-with-questions.webp)
- **Question filter.** One filter chip, *Question*, in the filter row of the
  Events section, a single-choice menu like Read state: *Any*, *Waiting*,
  *Answered*, *Closed* and *No question*. They are the list
  markers' words and map to `answerState` `OPEN`, `ANSWERED`, `CLOSED` and
  `NONE`. A chosen value shows in the chip with a check and is in the address.
  With nothing matching, the list says *No events match.* with *Clear filters*,
  as the other filters do. The page never says *To answer*.
- **Deleting** an event that asks says it in the confirmation: for an open
  question *NAME is waiting for an answer from Rodrigo or Ana. Its question goes
  with it, and PRODUCER gets no answer. This cannot be undone.*; for an answered
  one *Its question and Ana's answer are deleted too. This cannot be undone.*; a
  bulk delete *N events will be deleted, M of them with a question. Their
  questions and any answers go too. This cannot be undone.*
  [Q3](../answers/images/admin/q3-delete-an-event-that-asks-still.webp), [Q3b](../answers/images/admin/q3b-delete-several-events-some-ask.webp)
- **Send a test event** gets one folded section at the foot of its dialog, *Ask
  for an answer* (closed by default, so a plain test event is as short as before).
  Opened, it builds the question a producer would send: choices with labels (1 to
  100 characters), optional descriptions (up to 1000), *Note* or *Other* for the typed answer, and the id derived from the
  label by the one rule the SDK and the command use, *Pick* (*One* or *One or
  more*), *Note* (*None*, *Optional*, *Required*) and *Closes* (*Never*, *In* or
  *At*). *Typed answer as* (*Note* or *Other row*) shows only with at least one
  choice and *Note* not *None*; with *Other row*, *Note* is locked to *Optional*
  (*None* and *Required* dimmed, still focusable, with the help *With an Other
  row, typing is optional: the person picks a choice or Other.*). With no
  choices the Note control is replaced by *No choices: the answer is typed, and
  the person must type one.* Errors are on the field with an icon and a
  sentence, and a server refusal shows as a banner. After sending, the snack bar links to the event and says who
  was asked (*asking Rodrigo and Ana*). [D1q](../answers/images/admin/d1q-the-dialog-with-the-section-folded.webp), [D1b](../answers/images/admin/d1b-a-question-filled-in.webp),
  [D1c](../answers/images/admin/d1c-error-two-choices-with-the-same.webp), [D1d](../answers/images/admin/d1d-error-more-than-10-choices.webp), [D1e](../answers/images/admin/d1e-no-choices-the-answer-is-typed.webp), [D1f](../answers/images/admin/d1f-error-one-or-more-with-a.webp), [D1g](../answers/images/admin/d1g-closes-at-a-date-and-a.webp),
  [D2c](../answers/images/admin/d2c-sent-the-snack-bar-links-to.webp)
- **Who can answer on a producer** is a read-only row under *Allowed users*: the
  owner (tag *Owner*) and the answerers (tag *Answerer*), plain text and no
  controls, with one sentence saying it is set by the owner, in the app or on
  the web page.
  [P21](../answers/images/admin/p21-who-can-answer-the-owner-and.webp), [P22](../answers/images/admin/p22-who-can-answer-only-the-owner.webp)

### 10.8 Accessibility

- **Radios are one tab stop.** A single choice is a standard radio group. Tab
  enters it on the checked choice (the first when none is checked) and leaves it
  on the next Tab. The arrow keys move to the next or previous choice and check
  it, wrapping at the ends. Space checks the focused choice. In a multiple choice
  each checkbox is its own tab stop and Space toggles it. Then the note, then
  *Send answer*. [1n](../answers/images/web-answering/1n-keyboard-the-focus-ring-and-the.webp)
- **Enter in the note adds a line and never sends.** The answer goes only by the button, because
  it cannot be taken back. A typed-only question's text area takes Enter as a new
  line. Enter on the focused button sends. Escape does nothing. On the web page
  **Ctrl+Enter** (Cmd+Enter on a Mac) sends from anywhere in the card, as the
  button does, with the same checks; the button's tooltip names it.
  The shortcut is not the only way: the button works as always. It works from
  any control of the card, the note, the *Other* field and the typed answer
  included, and in a text area it does not insert a line. The button has
  `aria-keyshortcuts="Control+Enter Meta+Enter"` and its tooltip reads *Send
  answer (Ctrl+Enter)*, or *Send answer (Cmd+Enter)* on a Mac; it shows on
  hover and on keyboard focus of the button. A tooltip is not the only hint,
  so touch and screen reader users lose nothing. Ctrl+Enter does what a press
  does: with an error (nothing picked, past 3000 characters) it moves the
  focus and says why (10.3); while sending it is ignored; during an input
  method composition it does nothing. Because the note's field disappears
  when the card turns into the result, focus moves to the result's title
  (made focusable, `tabindex="-1"`) so keyboard focus is never lost; the
  result is announced once in the polite live region, whether it came from
  the button or from the shortcut. The app has no shortcut.
- **Accessible names.** A choice's name is its label and its state: *Merge,
  selected, 1 of 2*; a checkbox *Unit tests, checked* and *Lint, not checked*.
  Its description is its accessible description (`aria-describedby` on the web
  page, the hint on the app), read after the name and not repeated while focus
  moves inside the group. The group is named
  *Your answer*. The button while sending is *Sending answer*. A row of a
  question ends its name with its line: *Merge R82 into main?, Action required,
  High, ci-pipeline, 18:50, To answer, closes 09:00, unread*. The chip is *To
  answer, 2*. The close button of an answerer is *Remove Ana from Who can
  answer*.
  The *Other* row's field is named *Your answer for Other* (not the group's
  name), is tied to its counter and its error with `aria-describedby`, and the
  row's radio or checkbox has `aria-controls` pointing at it. Picking *Other*
  moves focus to the field; leaving it keeps the text (10.3).
- **Messages** (nothing picked, too long, the result) are tied to their field with
  `aria-describedby`; the too-long message, which appears while typing, is
  announced once politely; a message that comes with a focus move is not a live
  region. In the app, TalkBack's focus does not follow the focus move, so every
  message of the card (nothing picked, an empty *Other* field or typed answer,
  too long) is its own node and is spoken as it appears and at each press of
  *Send answer*: announced politely where Android takes announcements, and a
  live region where it does not (Android 16 and later). Every error
  has an icon and words, never colour alone.
- **Focus** follows 6.3: a 2 px primary ring, never removed, on the checked
  radio's row. A dialog starts on *Cancel* when it removes something.
- **Targets** are 48 dp (48 px on the web) for every row, chip and button.
- **Contrast and motion.** The light frames ([5a](../answers/images/app-answering/5a-light-theme-the-answer-card-1a.webp), [1i](../answers/images/notification/1i-light-theme-the-question-card.webp),
  [1o](../answers/images/web-answering/1o-1a-in-the-light-theme.webp), [Q1g](../answers/images/admin/q1g-q1b-in-the-light-theme.webp)) use the light tokens of section 9.6; every text
  pair passes 4.5:1. The sending ring stops turning for reduced motion (6.4).
