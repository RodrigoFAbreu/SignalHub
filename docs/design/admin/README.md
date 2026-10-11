# Designs for the operator's admin page

These are the designs R73 made for the operator's admin page (`/admin/`, on the
backend's own port) and for the users' web page's New producer action. The
admin page is rebuilt from them in later items. The owner approves them at the
design gate.

Everything is sample data. The host is `signalhub.example`. The people are
Rodrigo (admin), Ana (mod) and Rui (basic). The only keys look like
`shpk1_3f1c0b8e5d2a...` and are invented.

## What is here

| File | What it is |
| --- | --- |
| [WALKTHROUGH.md](WALKTHROUGH.md) | The operator's main flows step by step, with the choices made, the options not chosen, the server changes the designs need, and what was left out. |
| `images/` | One preview per screen and state: 146 images in WebP, in 8 folders. |
| [../users/DESIGN.md](../users/DESIGN.md#9-the-admin-page-r73) | The design system. Section 9 holds the admin page's rules (R1 to R8), components, light tokens, Status rules and motion. |
| [../users/source/](../users/source/README.md) | **The drawings themselves**, the source of truth: the `Admin - ...` pages, `Web - New producer action`, the five `admin-*.css` stylesheets and the changed design system page. They live with the users' drawings because it is one design project and one `vendor/` folder. The images here are previews of them. |

The designs were made in the same Claude Design project as the users' designs:
<https://claude.ai/design/p/17711c15-5ce6-495c-9841-de8eb831a828>

## How to read it

1. Start with [WALKTHROUGH.md](WALKTHROUGH.md). It follows nine flows and links
   each step to its frame.
2. Use [../users/DESIGN.md](../users/DESIGN.md#9-the-admin-page-r73) to check a
   rule, a component, a string or a duration.
3. Each image has an option or frame id in its top left (`A`, `P11`, `E2`, `G2`)
   and a note under the screen. The note has the exact copy and the rules. Ids
   are the same in the project and in the sources. Ids are unique within a
   folder, not across folders (`A` is the shell's option A in
   `shell-producers/` and Events' option A in `events/`).
4. Frames are dark unless they are in `images/light-theme/` or say so.
5. A dashed "Needs a server change" note in a frame means the design shows
   something the server does not provide today. See the table below.
6. Frames 1440 px wide are the desktop. Frames 390 px wide (ids starting `P18`
   to `P20`, `Q`, `PD`, `PG`, `PU`, `PC`, `PS` and `PT`) are the phone.
   Frames 480, 640 and 760 px wide are a detail pane or a dialog on its own.

## The owner's choices

| Question | Choice | Not chosen |
| --- | --- | --- |
| Layout of the page (2026-10-11) | A side navigation rail, with lists or tables at full width and a selected row opening a detail pane. Forms are dialogs or panes, never under a list. | Forms under a list, as the old page had. |
| Priority | Desktop first, usable at 390 px: no sideways scroll, the rail becomes a bottom bar, a detail is a full screen. | A separate mobile layout. |
| Shell | **A**: rail, table and a fixed 480 px pane (a side sheet below 1180 px). | B, a top bar with a rail and two-line rows. C, a full-width table with a 560 px side sheet. |
| Events | **A**: a dense table with filter chips and the pane. | B, grouped by day with a collapsible filter panel and endless scrolling. C, a facet sidebar with saved quick filters. |
| Web page's New producer | **A**: a tonal button in the list header. | B, the floating button kept and shrunk while scrolling. C, a card at the end of the list. |
| Server changes | Small ones are allowed. Each is listed here and queued as its own item. | None. |
| Themes | Dark first, light for the key screens. | |

## The server changes the designs need

Each is a dashed "Needs a server change" note in the frames. Everything else
drawn exists in the management API today. The owner approves this list at the
design gate. Each approved item is queued as its own server item.

| Id | Item | Size | Where it shows |
| --- | --- | --- | --- |
| S1 | Pairings: list the open admin-created codes, and cancel an unused one. Today only the code just made can be watched, and closing the dialog loses it. | small | [G2](images/devices/g2-the-pairing-code-waiting.webp), [DV1](images/devices/dv1-list-with-a-device-selected.webp) |
| S2a | Producers: an optional `name` on the admin producer update (rename). Today only the owner can rename, from a device. | small | [A](images/shell-producers/a-rail-table-and-a-fixed-detail.webp), [P12b](images/shell-producers/p12b-rename-producer-the-name-is-taken.webp) |
| S2b | Producers: `disabledBy` (the owner or an admin) in the admin producer response, so the banner can say "Disabled by its owner" or "Disabled by the host". | tiny | [P2](images/shell-producers/p2-a-disabled-producer-technical-details-open.webp) |
| S3 | Status: `startedAt` in `/api/v1/admin/status`, for the "Running since" row. | small | [ST1](images/status-sign-in/st1-working.webp), [ST2](images/status-sign-in/st2-needs-attention-the-push-service-is.webp), [PT1](images/status-sign-in/pt1-phone-working-one-row-opened.webp) |
| S7 | Deliveries: a `final` marker (gave up) on delivery records. Until then the page tells "Gave up after 5 tries" from the attempt count (5 is the server's limit). | small | [E2b](images/events/e2b-the-pushes-tab-the-other-wordings.webp), [DV2](images/devices/dv2-a-push-problem-technical-details-open.webp) |
| S4 | Events: a total count for the list ("25 of 1,284"). Optional. Until then the header says "Newest first". | small to medium | [A](images/events/a-dense-table-chips-and-a-fixed.webp), [S5](images/events/s5-filtered-severity-critical-and-unread-only.webp) |
| E-OUTCOME | Events: each event's push outcome summary in the list, and a filter by outcome. Optional. It feeds the Push problems chip and the row marker. | medium | [A](images/events/a-dense-table-chips-and-a-fixed.webp), [S5](images/events/s5-filtered-severity-critical-and-unread-only.webp) |

Dropped: per-user allow-list endpoints (reading, changing and replacing the
list is enough), per-provider push counters, an abandoned-retries window (the
page counts since it was opened instead), reusing a revoked user's name (the
copy says the name stays taken), and facet counts (option C was not chosen).

Rules the owner approves with the designs, which are not server changes: the
Status "needs attention" rules, and that "push not set up" counts as needing
attention ([DESIGN.md 9.5](../users/DESIGN.md#95-status-when-signalhub-needs-attention)).

## Screen families

### Shell and Producers

Folder `images/shell-producers/`, 26 images. Drawn in `Admin - Shell and Producers`. Three shell options (A chosen), the account menu and sign-out, the Producers list, detail, states and dialogs, and the phone frames.

- [A](images/shell-producers/a-rail-table-and-a-fixed-detail.webp): Rail, table and a fixed detail pane
- [B](images/shell-producers/b-top-bar-rail-twoline-list-and.webp): Top bar, rail, two-line list and a wide detail
- [C](images/shell-producers/c-rail-fullwidth-table-and-a-side.webp): Rail, full-width table and a side sheet
- [M1](images/shell-producers/m1-the-account-menu-option-a.webp): The account menu (option A)
- [M2](images/shell-producers/m2-sign-out-confirmed.webp): Sign out, confirmed
- [P1](images/shell-producers/p1-list-with-a-filter-chip-active.webp): List with a filter chip active, nothing selected
- [P2](images/shell-producers/p2-a-disabled-producer-technical-details-open.webp): A disabled producer, technical details open
- [P3](images/shell-producers/p3-quiet-with-every-key-revoked.webp): Quiet, with every key revoked
- [P4](images/shell-producers/p4-loading.webp): Loading
- [P5](images/shell-producers/p5-empty-no-producer-exists.webp): Empty: no producer exists
- [P6](images/shell-producers/p6-empty-nothing-matches.webp): Empty: nothing matches
- [P7](images/shell-producers/p7-the-list-failed-to-load-with.webp): The list failed to load, with an older list under it
- [P8](images/shell-producers/p8-success-a-change-confirmed-in-the.webp): Success: a change confirmed in the pane
- [P9](images/shell-producers/p9-failure-a-change-that-did-not.webp): Failure: a change that did not happen, in the pane
- [P10](images/shell-producers/p10-keyboard-focus.webp): Keyboard focus
- [P11](images/shell-producers/p11-new-producer-a-dialog.webp): New producer: a dialog
- [P12](images/shell-producers/p12-new-producer-the-name-is-taken.webp): New producer: the name is taken
- [P12b](images/shell-producers/p12b-rename-producer-the-name-is-taken.webp): Rename producer: the name is taken
- [P13](images/shell-producers/p13-the-key-shown-once.webp): The key, shown once
- [P14](images/shell-producers/p14-confirm-revoke-a-key-replaces-the.webp): Confirm: revoke a key (replaces the browser's confirm())
- [P15](images/shell-producers/p15-confirm-disable-a-producer.webp): Confirm: disable a producer
- [P16](images/shell-producers/p16-confirm-public-to-private.webp): Confirm: public to private
- [P17](images/shell-producers/p17-confirm-remove-someone-from-the-list.webp): Confirm: remove someone from the list
- [P18](images/shell-producers/p18-phone-the-list-390-wide.webp): Phone: the list (390 wide)
- [P19](images/shell-producers/p19-phone-the-detail-full-screen.webp): Phone: the detail, full screen
- [P20](images/shell-producers/p20-phone-new-producer-full-screen.webp): Phone: New producer, full screen

### Events

Folder `images/events/`, 33 images. Drawn in `Admin - Events, Admin - Events states, Admin - Events dialogs`. Three options for browsing events (A chosen), an event's detail with its pushes, selecting and deleting, filters, states, the send-a-test-event and delete-by-rule dialogs, and the phone frames.

- [A](images/events/a-dense-table-chips-and-a-fixed.webp): Dense table, chips and a fixed pane
- [B](images/events/b-grouped-by-day-collapsible-filters.webp): Grouped by day, collapsible filters
- [C](images/events/c-facet-sidebar-and-saved-quick-filters.webp): Facet sidebar and saved quick filters
- [E1](images/events/e1-the-event-tab-what-was-sent.webp): The event tab: what was sent
- [E2](images/events/e2-the-pushes-tab-who-it-reached.webp): The pushes tab: who it reached, device by device
- [E2b](images/events/e2b-the-pushes-tab-the-other-wordings.webp): The pushes tab: the other wordings
- [E3](images/events/e3-the-pushes-tab-with-technical-details.webp): The pushes tab with Technical details open
- [E4](images/events/e4-pushes-tab-nobody-to-reach-and.webp): Pushes tab: nobody to reach, and not yet dispatched
- [E5](images/events/e5-pushes-tab-the-list-could-not.webp): Pushes tab: the list could not be loaded
- [Q1](images/events/q1-phone-the-list.webp): Phone: the list
- [Q2](images/events/q2-phone-the-detail-full-screen.webp): Phone: the detail, full screen
- [Q3](images/events/q3-phone-send-a-test-event-a.webp): Phone: Send a test event, a full-screen dialog
- [Q4](images/events/q4-phone-the-filters-sheet.webp): Phone: the filters sheet
- [S1](images/events/s1-three-events-selected-the-bulk-bar.webp): Three events selected: the bulk bar
- [S2](images/events/s2-delete-the-selection-the-confirmation.webp): Delete the selection: the confirmation
- [S3](images/events/s3-the-header-menu-delete-events-by.webp): The header menu: Delete events by rule
- [S4](images/events/s4-a-filter-chip-open-severity-several.webp): A filter chip open (Severity): several choices
- [S4b](images/events/s4b-the-received-chip-open-a-date.webp): The Received chip open: a date range
- [S5](images/events/s5-filtered-severity-critical-and-unread-only.webp): Filtered: Severity Critical and Unread only
- [L1](images/events/l1-loading-the-first-page.webp): Loading the first page
- [L2](images/events/l2-empty-no-events-at-all.webp): Empty: no events at all
- [L3](images/events/l3-no-match-for-the-filters.webp): No match for the filters
- [L4](images/events/l4-error-refresh-failed-older-list-kept.webp): Error: refresh failed, older list kept with a banner
- [L5](images/events/l5-error-the-first-load-failed.webp): Error: the first load failed
- [F1](images/events/f1-success-deleted-3-events.webp): Success: Deleted 3 events
- [F2](images/events/f2-keyboard-focus.webp): Keyboard focus
- [D1](images/events/d1-send-a-test-event.webp): Send a test event
- [D2](images/events/d2-send-a-test-event-invalid-metadata.webp): Send a test event: invalid metadata
- [D2b](images/events/d2b-sent-the-result.webp): Sent: the result
- [D6](images/events/d6-delete-by-rule-ready-to-count.webp): Delete by rule: ready to count
- [D3](images/events/d3-delete-by-rule-no-rule-chosen.webp): Delete by rule: no rule chosen
- [D4](images/events/d4-delete-by-rule-the-dryrun-count.webp): Delete by rule: the dry-run count, then confirm
- [D5](images/events/d5-delete-by-rule-nothing-to-delete.webp): Delete by rule: nothing to delete

### Devices

Folder `images/devices/`, 26 images. Drawn in `Admin - Devices, Admin - Devices dialogs`. The device list and detail, push problems, signed-in browsers, states, connecting a device with a pairing code, rename, revoke and delete, and the phone frames.

- [DV1](images/devices/dv1-list-with-a-device-selected.webp): List with a device selected
- [DV2](images/devices/dv2-a-push-problem-technical-details-open.webp): A push problem, Technical details open
- [DV3](images/devices/dv3-a-signedin-browser.webp): A signed-in browser
- [DV4](images/devices/dv4-a-revoked-device-delete-is-offered.webp): A revoked device: Delete is offered
- [DS1](images/devices/ds1-loading.webp): Loading
- [DS2](images/devices/ds2-empty-no-device-yet.webp): Empty: no device yet
- [DS3](images/devices/ds3-no-match-for-the-search-or.webp): No match for the search or filters
- [DS4](images/devices/ds4-refresh-failed-banner-over-the-older.webp): Refresh failed: banner over the older list
- [DS5](images/devices/ds5-success-a-snack-bar-and-the.webp): Success: a snack bar and the new value in the pane
- [DS6](images/devices/ds6-keyboard-focus.webp): Keyboard focus
- [PD1](images/devices/pd1-the-list.webp): The list
- [PD2](images/devices/pd2-the-detail-full-screen.webp): The detail, full screen
- [PD3](images/devices/pd3-the-pairing-code-full-screen.webp): The pairing code, full screen
- [G1](images/devices/g1-connect-a-device.webp): Connect a device
- [G1b](images/devices/g1b-connect-the-admindevice-sentence.webp): Connect: the admin-device sentence
- [G1c](images/devices/g1c-the-code-without-a-link-no.webp): The code without a link: no public address set
- [G2](images/devices/g2-the-pairing-code-waiting.webp): The pairing code, waiting
- [G3](images/devices/g3-the-code-expired.webp): The code expired
- [G4](images/devices/g4-the-code-was-used.webp): The code was used
- [G5](images/devices/g5-rename.webp): Rename
- [G6](images/devices/g6-revoke-an-admin-device.webp): Revoke an admin device
- [G6b](images/devices/g6b-revoke-it-did-not-work.webp): Revoke: it did not work
- [G7](images/devices/g7-delete-a-revoked-device.webp): Delete a revoked device
- [PG1](images/devices/pg1-connect-a-device-full-screen.webp): Connect a device, full screen
- [PG2](images/devices/pg2-revoke-as-a-bottom-sheet.webp): Revoke, as a bottom sheet
- [PG3](images/devices/pg3-the-code-was-used.webp): The code was used

### Users

Folder `images/users/`, 27 images. Drawn in `Admin - Users, Admin - Users dialogs`. The user list and detail with role, devices, producers, subscriptions and recent traffic, invite, role changes, subscribe and unsubscribe, revoke and rename, and the phone frames.

- [U1](images/users/u1-list-with-a-user-selected.webp): List with a user selected
- [U2](images/users/u2-the-same-pane-scrolled-down.webp): The same pane, scrolled down
- [U3](images/users/u3-invited-no-device-yet.webp): Invited, no device yet
- [U4](images/users/u4-an-admin-and-a-revoked-user.webp): An admin, and a revoked user
- [US1](images/users/us1-loading.webp): Loading
- [US2](images/users/us2-empty-and-no-match.webp): Empty, and no match
- [US3](images/users/us3-refresh-failed-over-the-older-list.webp): Refresh failed over the older list, and a traffic error in the pane
- [US4](images/users/us4-success-role-changed-and-keyboard-focus.webp): Success (role changed) and keyboard focus on the role choice
- [PU1](images/users/pu1-the-list.webp): The list
- [PU2](images/users/pu2-the-detail-full-screen.webp): The detail, full screen
- [PU3](images/users/pu3-invite-a-user-full-screen.webp): Invite a user, full screen
- [UD1](images/users/ud1-invite-a-user.webp): Invite a user
- [UD1b](images/users/ud1b-invite-admin-chosen.webp): Invite: Admin chosen
- [UD1c](images/users/ud1c-invite-that-name-is-taken-409.webp): Invite: that name is taken (409)
- [UD2](images/users/ud2-step-2-connect-their-first-device.webp): Step 2: connect their first device
- [UD3](images/users/ud3-invite-it-did-not-work.webp): Invite: it did not work
- [UC1](images/users/uc1-make-a-user-a-mod.webp): Make a user a Mod
- [UC2](images/users/uc2-make-a-user-an-admin.webp): Make a user an Admin
- [UC3](images/users/uc3-take-admin-away-the-last-admin.webp): Take Admin away (the last admin)
- [UC4](images/users/uc4-unsubscribe.webp): Unsubscribe
- [UC5](images/users/uc5-subscribe-the-choice-of-producer.webp): Subscribe: the choice of producer
- [UC6](images/users/uc6-revoke-a-user.webp): Revoke a user
- [UC7](images/users/uc7-rename-a-user.webp): Rename a user
- [UC7b](images/users/uc7b-rename-that-name-is-taken-409.webp): Rename: that name is taken (409)
- [PC1](images/users/pc1-a-role-change-as-a-sheet.webp): A role change, as a sheet
- [PC2](images/users/pc2-subscribe-as-a-sheet.webp): Subscribe, as a sheet
- [PC3](images/users/pc3-invited-connect-the-first-device.webp): Invited: connect the first device

### Status and sign-in

Folder `images/status-sign-in/`, 21 images. Drawn in `Admin - Status and sign-in, Admin - Status, Admin - Status states`. The sign-in screen and its problems, the Status page (working, needs attention, technical details), its other states, the rail button states, and the phone frames.

- [SI1](images/status-sign-in/si1-the-first-screen-the-field-has.webp): The first screen, the field has the keyboard
- [SI2](images/status-sign-in/si2-wrong-token-the-server-answered-401.webp): Wrong token (the server answered 401)
- [SI3](images/status-sign-in/si3-the-management-api-is-off-the.webp): The management API is off (the server answered 404)
- [SI4](images/status-sign-in/si4-the-server-cannot-be-reached.webp): The server cannot be reached
- [SI5](images/status-sign-in/si5-signing-in-waiting-for-the-server.webp): Signing in (waiting for the server)
- [SI6](images/status-sign-in/si6-signed-out-after-the-signout-dialog.webp): Signed out (after the sign-out dialog, M2)
- [SI7](images/status-sign-in/si7-the-session-was-lost-the-token.webp): The session was lost (the token stopped working while in use)
- [PS1](images/status-sign-in/ps1-phone-the-first-screen.webp): Phone: the first screen
- [PS2](images/status-sign-in/ps2-phone-wrong-token.webp): Phone: wrong token
- [PS3](images/status-sign-in/ps3-phone-the-management-api-is-off.webp): Phone: the management API is off
- [PS4](images/status-sign-in/ps4-phone-the-session-was-lost.webp): Phone: the session was lost
- [ST1](images/status-sign-in/st1-working.webp): Working
- [ST2](images/status-sign-in/st2-needs-attention-the-push-service-is.webp): Needs attention: the push service is failing and its retries are being given up
- [ST4](images/status-sign-in/st4-technical-details-open-the-page-scrolled.webp): Technical details open (the page scrolled to its end)
- [ST3](images/status-sign-in/st3-other-rows-that-need-a-look.webp): Other rows that need a look (each shown inside the page's column)
- [ST5](images/status-sign-in/st5-loading-the-first-time-the-page.webp): Loading (the first time the page is opened)
- [ST6](images/status-sign-in/st6-the-status-could-not-be-read.webp): The status could not be read at all
- [RB1](images/status-sign-in/rb1-working-check-checking-unknown.webp): Working, Check, Checking, Unknown
- [PT1](images/status-sign-in/pt1-phone-working-one-row-opened.webp): Phone: working, one row opened
- [PT2](images/status-sign-in/pt2-phone-needs-attention.webp): Phone: needs attention
- [PT3](images/status-sign-in/pt3-phone-could-not-be-read.webp): Phone: could not be read

### Light theme

Folder `images/light-theme/`, 8 images. Drawn in `Admin - Light theme check`. The key admin screens in the light theme, with a contrast table in the page.

- [LA1](images/light-theme/la1-shell-a-the-producers-list-and.webp): Shell A: the Producers list and its detail pane
- [LA2](images/light-theme/la2-a-disabled-producer-technical-details-open.webp): A disabled producer, technical details open
- [LE1](images/light-theme/le1-events-a-an-events-detail-pushes.webp): Events A: an event's detail, Pushes tab
- [LS1](images/light-theme/ls1-status-st1-signalhub-is-working.webp): Status ST1: SignalHub is working
- [LS2](images/light-theme/ls2-status-st2-needs-attention.webp): Status ST2: needs attention
- [LI1](images/light-theme/li1-sign-in-si1-the-first-screen.webp): Sign in SI1: the first screen
- [LG1](images/light-theme/lg1-the-pairing-code-dialog-g2.webp): The pairing code dialog (G2)
- [LW1](images/light-theme/lw1-the-web-pages-new-producer-option.webp): The web page's New producer, option A, at 1440 and 390

### The web page's New producer action

Folder `images/web-new-producer/`, 4 images. Drawn in `Web - New producer action`. Where the users' web page puts New producer so that it never covers a producer: three options (A chosen) and A in light.

- [9a](images/web-new-producer/9a-a-a-tonal-new-producer-button.webp): A. A tonal New producer button in the list header (chosen). No floating button.
- [9b](images/web-new-producer/9b-b-keep-the-floating-button-reserve.webp): B. Keep the floating button, reserve space under the last row, and shrink it to an icon while scrolling down.
- [9c](images/web-new-producer/9c-c-a-new-producer-card-at.webp): C. A New producer card at the end of the list, after the last producer. No floating button.
- [9d](images/web-new-producer/9d-option-a-in-the-light-theme.webp): Option A in the light theme, 1440 and 390, scrolled to the end

### Design system, Admin page section

Folder `images/design-system-admin/`, 1 images. Drawn in `SignalHub Design System`. The design system page's new Admin page section: components, rules R1 to R6, wording and motion.

- [s12](images/design-system-admin/s12-admin-page.webp): Admin page
