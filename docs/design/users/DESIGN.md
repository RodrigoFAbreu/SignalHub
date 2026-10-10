# SignalHub design system

This is the design system for SignalHub's app and web page. It records the
look the released app already has (version 2.26.6) and the patterns added for
users in R64. New screens extend it. They do not restyle it.

The source is the `SignalHub Design System` page in the Claude Design project.
Section images of that page are in `images/design-system/`. A few frames show
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
  Subscribed, Can subscribe. A selected chip is secondaryContainer with a check.
  Chips never wrap. A chip's hit area is padded to 48 dp.
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

![s5: Patterns added for users](images/design-system/s5-patterns-added-users.webp)

### 3.3 Feedback and state components

![s6: Feedback and state components](images/design-system/s6-feedback-state-components.webp)

**Snackbar** (plain, with Retry, with Undo). One or two lines, at most one
action, gone after 6 seconds. It floats 8 dp above the bottom bar. Plain says a
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
field is valid.

**Banners.** Error (errorContainer): something stopped and there is a next
step. Offline (neutral): reading still works and anything that writes is greyed.
Stale (neutral, with Try again): the refresh failed, so the older list stays
with its time. A banner sits under the app bar and search, above the list. It
is inline: it pushes the list down and never covers it.
Tokens: radius 12, minimum height 56, icon 24, action 48 high text button.

**Loading.** A list that loads shows skeleton rows with the shape of the real
row, at least three. Never a spinner for a whole list. A button that works keeps
its width and label, shows a spinner in its icon slot and ignores taps. Screens
that need a name in the title wait for it.

**Bell toggle.** One control per producer row for subscribing, in place. A tap
swaps the bell for a progress ring and ignores taps until the call ends. On
failure it goes back to what it was, and a snackbar with Retry says so. Offline
it is greyed. The bell stays on a paused or disabled producer so it can be
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
(`Inbox, 124 unread`).

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
header. There is no snackbar with Undo: the page confirms instead and shows a
failed change inline. The key dialog is the exception. Escape and a tap on the
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

If an action can be reversed exactly and only the person who did it is
affected, do it at once and offer Undo in a snackbar. If it cannot be reversed,
or someone else is affected, ask first in a confirmation dialog. If it is
harmless and reversible by the same control, add nothing.

| Action | Pattern | Why |
| --- | --- | --- |
| Subscribe, unsubscribe | Snackbar with Undo | Idempotent. Stored events are hidden, not deleted. |
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
- Dialogs and sheets scroll. Buttons grow and their labels wrap. Keys and
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
