# Designs for users in the app and on a web page

These are the designs R64 made for SignalHub's user features: people with
roles, their own producers and keys, subscribing, devices by role, and a web
page that signs in by pairing the browser. The Flutter app (R65) and the web
page (R66) build what is drawn here. G4 is where the maintainer approves it.

Everything is sample data. The host is `signalhub.example`. The only key is
`shpk1_EXAMPLEKEY-not-a-real-key-0000`.

## What is here

| File | What it is |
| --- | --- |
| [DESIGN.md](DESIGN.md) | The design system: tokens, components, patterns, wording, accessibility, contrast, and R64's rules. |
| [WALKTHROUGH.md](WALKTHROUGH.md) | The main flows step by step, with the choices made, the alternatives, what the server must provide, and what was left out. |
| `images/` | One image per screen and state: 147 images in WebP, in 9 folders. |

The designs were made in a Claude Design project, with a design system page,
nine screen pages and two clickable prototypes:
<https://claude.ai/design/p/17711c15-5ce6-495c-9841-de8eb831a828>

## How to read it

1. Start with [WALKTHROUGH.md](WALKTHROUGH.md). It follows seven flows and links
   each step to its frame.
2. Use [DESIGN.md](DESIGN.md) to check a token, a component or a string.
3. Each image has an option id in its top left (`3b`, `2b`, `6a`) and a note
   under the screen. The note has the exact copy and the rules. Ids are the same
   in the project.
4. Frames are dark unless the file name says otherwise. The light theme is in
   `images/light-theme/`.
5. A dashed "R66 decides" or "Needs a server change" note in a frame means the
   design leaves that detail to a later item.

## Screen families

### App: first run, setup, empty states, errors, offline, notifications

Folder `images/first-run/`, 24 images.

- [4a](images/first-run/4a-setup-scan-invitation.webp): Setup: scan the invitation
- [4b](images/first-run/4b-welcome-once.webp): Welcome, once
- [4c](images/first-run/4c-empty-inbox-nothing-subscribed.webp): Empty inbox, nothing subscribed
- [4d](images/first-run/4d-producers-none-all-yet.webp): Producers: none at all yet
- [4g](images/first-run/4g-producers-nothing-under-yours.webp): Producers: nothing under Yours
- [4h](images/first-run/4h-producers-nothing-under-can-subscribe.webp): Producers: nothing under Can subscribe
- [4e](images/first-run/4e-code-that-doesnt-work.webp): A code that doesn't work
- [4f](images/first-run/4f-this-device-no-longer-connected.webp): This device is no longer connected
- [4a2](images/first-run/4a2-camera-not-allowed.webp): Camera not allowed
- [4a3](images/first-run/4a3-code-that-isnt-invitation.webp): A code that isn't an invitation
- [4a4](images/first-run/4a4-cant-reach-server.webp): Can't reach the server
- [4a6](images/first-run/4a6-client-key-wrong-key.webp): With a client key, and a wrong key
- [4b2](images/first-run/4b2-welcome-admins-device.webp): Welcome, an admin's device
- [4b3](images/first-run/4b3-whats-new-once-after-upgrade.webp): What's new, once, after the upgrade
- [4b4](images/first-run/4b4-settings-about-this-server-row.webp): Settings: the About this server row
- [4b5](images/first-run/4b5-about-this-server.webp): About this server
- [4i](images/first-run/4i-list-that-didnt-load.webp): A list that didn't load
- [4j](images/first-run/4j-offline-showing-older-list.webp): Offline, showing an older list
- [4j2](images/first-run/4j2-change-flight-one-that-failed.webp): A change in flight, and one that failed
- [4l](images/first-run/4l-loading-list-button-working.webp): Loading a list, and a button working
- [4m](images/first-run/4m-screen-your-role-doesnt-have.webp): A screen your role doesn't have
- [4m2](images/first-run/4m2-action-your-role-doesnt-allow.webp): An action your role doesn't allow
- [4o](images/first-run/4o-event-that-isnt-your-inbox.webp): An event that isn't in your inbox any more
- [4n](images/first-run/4n-shade-event-four-notices.webp): The shade: an event, and four notices

### App: bottom navigation, the Producers tab, the row in each state, a producer's events

Folder `images/producers/`, 12 images.

- [1a](images/producers/1a-inbox-bar-basic-mod.webp): Inbox with the bar (Basic and Mod)
- [1d](images/producers/1d-producers-search-filter-chips.webp): Producers: search and filter chips
- [1f](images/producers/1f-producers-search-no-results.webp): Producers: a search with no results
- [1e](images/producers/1e-bar-admin-people-added-settings.webp): The bar for an admin: People added, and Settings in its one order
- [1g](images/producers/1g-row-each-state.webp): The row in each state
- [1h](images/producers/1h-subscribing-flight.webp): Subscribing: in flight
- [1i](images/producers/1i-subscribing-it-failed.webp): Subscribing: it failed
- [1j](images/producers/1j-unsubscribed-undo.webp): Unsubscribed, with Undo
- [1n](images/producers/1n-360dp-wide-text-200.webp): 360dp wide, text at 200 %
- [1k](images/producers/1k-badge-sizes-bar-basic-then.webp): Badge sizes on the bar (Basic, then Admin with four tabs)
- [1l](images/producers/1l-events-ci-pipeline.webp): Events of ci-pipeline
- [1m](images/producers/1m-no-events-from-it-yet.webp): No events from it yet

### App: new producer, the key shown once, your producer, someone else's producer, dialogs

Folder `images/new-producer-key/`, 30 images.

- [2a](images/new-producer-key/2a-new-producer.webp): New producer
- [2b](images/new-producer-key/2b-key-full-screen-you-leave.webp): Key: a full screen you leave on purpose
- [2e](images/new-producer-key/2e-your-producer.webp): Your producer
- [2e1](images/new-producer-key/2e1-your-producer-nobody-added-yet.webp): Your producer, nobody added yet
- [2f](images/new-producer-key/2f-add-people-private-producer.webp): Add people to a private producer
- [2g](images/new-producer-key/2g-someone-elses-producer-subscribed.webp): Someone else's producer, subscribed
- [2a1](images/new-producer-key/2a1-create-name-taken.webp): Create: the name is taken
- [2a2](images/new-producer-key/2a2-create-name-not-allowed.webp): Create: the name is not allowed
- [2h](images/new-producer-key/2h-rename-pencil-producers-screen.webp): Rename: the pencil on the producer's screen
- [2i](images/new-producer-key/2i-revoke-key.webp): Revoke a key
- [2j](images/new-producer-key/2j-revoke-only-working-key.webp): Revoke the only working key
- [2k](images/new-producer-key/2k-disable-producer.webp): Disable the producer
- [2l](images/new-producer-key/2l-remove-someone-from-list.webp): Remove someone from the list
- [2m](images/new-producer-key/2m-public-private.webp): Public to Private
- [2n](images/new-producer-key/2n-every-key-revoked.webp): Every key revoked
- [2o](images/new-producer-key/2o-disabled-by-you.webp): Disabled by you
- [2p](images/new-producer-key/2p-disabled-by-host.webp): Disabled by the host
- [2q](images/new-producer-key/2q-producer-that-isnt-available-any.webp): A producer that isn't available any more
- [2g1](images/new-producer-key/2g1-not-subscribed-yet.webp): Not subscribed yet
- [2g2](images/new-producer-key/2g2-shared-you-muted-this-device.webp): Shared with you, and muted on this device
- [2g3](images/new-producer-key/2g3-owner-who-unsubscribed.webp): The owner, who unsubscribed
- [2b1](images/new-producer-key/2b1-after-copy.webp): After Copy
- [2b2](images/new-producer-key/2b2-back-before-copying.webp): Back, before copying
- [2b3](images/new-producer-key/2b3-answer-was-lost-create-again.webp): The answer was lost: Create again
- [2b4](images/new-producer-key/2b4-producer-no-key.webp): The producer, with no key
- [2b5](images/new-producer-key/2b5-new-key-existing-producer.webp): New key for an existing producer
- [2b6](images/new-producer-key/2b6-360dp-wide-text-200.webp): 360dp wide, text at 200 %
- [2f1](images/new-producer-key/2f1-nobody-else-server.webp): Nobody else on the server
- [2f2](images/new-producer-key/2f2-many-people-search-failed-save.webp): Many people: search, and a failed save
- [2f3](images/new-producer-key/2f3-save-when-it-removes-someone.webp): Save, when it removes someone

### App: People, invite, a person, Devices by role, connect a device

Folder `images/people-devices/`, 30 images.

- [3b](images/people-devices/3b-people-tab-sections-by-role.webp): People tab: sections by role
- [3b2](images/people-devices/3b2-360dp-wide-text-200.webp): 360dp wide, text at 200 %
- [3d0](images/people-devices/3d0-invite-someone-form.webp): Invite someone: the form
- [3d](images/people-devices/3d-invite-someone-code.webp): Invite someone: the code
- [3e](images/people-devices/3e-person-admin-sees-them.webp): A person, as an admin sees them
- [3f](images/people-devices/3f-devices-mod-their-own.webp): Devices for a Mod: their own
- [3g](images/people-devices/3g-devices-basic-user.webp): Devices for a Basic user
- [3d2](images/people-devices/3d2-invite-name-taken.webp): Invite: the name is taken
- [3d3](images/people-devices/3d3-invite-joined.webp): Invite: joined
- [3d4](images/people-devices/3d4-invite-code-ran-out.webp): Invite: the code ran out
- [3e2](images/people-devices/3e2-another-admin-read-only.webp): Another admin, read only
- [3e3](images/people-devices/3e3-changing-role-asks-first.webp): Changing a role asks first
- [3e4](images/people-devices/3e4-role-device-errors-messages.webp): Role and device errors, as messages
- [3e5](images/people-devices/3e5-this-person-was-removed.webp): This person was removed
- [3h](images/people-devices/3h-devices-admin-grouped-by-person.webp): Devices for an admin: grouped by person
- [3h2](images/people-devices/3h2-rename-device.webp): Rename a device
- [3h3](images/people-devices/3h3-revoke-device.webp): Revoke a device
- [3h4](images/people-devices/3h4-delete-revoked-device.webp): Delete a revoked device
- [3h5](images/people-devices/3h5-long-device-name-360dp-text.webp): A long device name, 360dp, text at 200 %
- [3f2](images/people-devices/3f2-mods-last-active-device.webp): A Mod's last active device
- [3i0](images/people-devices/3i0-connect-device-mod-step-one.webp): Connect a device: a Mod, step one
- [3i](images/people-devices/3i-connect-device-mod-code.webp): Connect a device: a Mod, the code
- [3i2](images/people-devices/3i2-connect-device-admin-chooses-who.webp): Connect a device: an admin chooses who
- [3i5](images/people-devices/3i5-connect-device-code-someone-else.webp): Connect a device: the code for someone else
- [3i3](images/people-devices/3i3-connect-device-used.webp): Connect a device: used
- [3i4](images/people-devices/3i4-connect-device-ran-out-refused.webp): Connect a device: ran out, and refused
- [3p](images/people-devices/3p-settings-sign-browser-basic-user.webp): Settings: Sign in a browser (a Basic user)
- [3g2](images/people-devices/3g2-basic-user-signs-out-their.webp): A Basic user signs out their browser
- [3j](images/people-devices/3j-people-search-pull-refresh.webp): People: search, and pull to refresh
- [3k](images/people-devices/3k-your-role-changed-while-app.webp): Your role changed while the app was open

### App: the light theme for key screens, plus the web sign-in and Settings in light

Folder `images/light-theme/`, 14 images.

- [5a](images/light-theme/5a-inbox.webp): Inbox
- [5b](images/light-theme/5b-producers-search-chips.webp): Producers (search and chips)
- [5c](images/light-theme/5c-key-shown-once-full-screen.webp): Key shown once (full screen)
- [5d](images/light-theme/5d-people-3b-sections-by-role.webp): People (3b, sections by role)
- [5e](images/light-theme/5e-producers-row-each-state.webp): Producers: the row in each state
- [5f](images/light-theme/5f-confirmation-dialog-revoke-key.webp): Confirmation dialog: revoke a key
- [5g](images/light-theme/5g-snackbar-change-failed-retry.webp): Snackbar: a change failed, with Retry
- [5h](images/light-theme/5h-offline-banner-older-list.webp): Offline banner: an older list
- [5i](images/light-theme/5i-error-banner-disabled-by-host.webp): Error banner: disabled by the host
- [6a-l](images/light-theme/6a-l-sign-desktop-browser.webp): Sign in on a desktop browser
- [6d-l](images/light-theme/6d-l-sign-phones-own-browser.webp): Sign in on a phone's own browser
- [8a-l](images/light-theme/8a-l-settings-desktop-this-browser-devices.webp): Settings on a desktop: this browser, Devices, About this server
- [8c-l](images/light-theme/8c-l-revoke-browser-confirmation-web-page.webp): Revoke a browser: the confirmation on the web page
- [6f-l](images/light-theme/6f-l-web-banner-sign-ended-offline.webp): The web banner: sign-in ended, and offline

### Web: signing in (desktop and phone), problems, ended sessions

Folder `images/web-sign-in/`, 8 images.

- [6a](images/web-sign-in/6a-page-waits-app-scans.webp): The page waits; the app scans
- [6a2](images/web-sign-in/6a2-code-expires-refreshes-itself.webp): The code expires and refreshes itself
- [6a3](images/web-sign-in/6a3-app-asks-sign-this-browser.webp): The app asks: Sign in this browser?
- [6a4](images/web-sign-in/6a4-success-page-opens-inbox.webp): Success: the page opens the inbox
- [6a5](images/web-sign-in/6a5-desktop-use-code-instead.webp): On a desktop: Use a code instead
- [6d](images/web-sign-in/6d-signing-phones-own-browser-type.webp): Signing in on a phone's own browser: type a short code in the app, or open the app
- [6e](images/web-sign-in/6e-when-something-not-right-while.webp): When something is not right while signing in
- [6f](images/web-sign-in/6f-signed-out-while-using-page.webp): Signed out while using the page: the 30 days ended, the browser was revoked, or a sign-out in another tab

### Web: inbox and Producers on a desktop and at phone width

Folder `images/web-inbox-producers/`, 8 images.

- [7a](images/web-inbox-producers/7a-inbox-desktop-admins-rail-list.webp): Inbox on a desktop (an admin's rail): list and the open event
- [7b](images/web-inbox-producers/7b-producers-desktop-search-chips-your.webp): Producers on a desktop: search, chips, your producer open beside the list, the account menu open
- [7c](images/web-inbox-producers/7c-web-page-phone-inbox-account.webp): The web page on a phone: inbox with the account button (an admin's bar)
- [7d](images/web-inbox-producers/7d-web-page-phone-producers-account.webp): The web page on a phone: Producers, account menu open
- [7e](images/web-inbox-producers/7e-producer-yours-phone-width-address.webp): A producer of yours at phone width, at an address that uses its id
- [7f](images/web-inbox-producers/7f-new-producer-phone-width-someone.webp): New producer at phone width, and someone else's producer
- [7h](images/web-inbox-producers/7h-producer-that-only-yours-public.webp): A producer that is only yours, and a public one
- [7g](images/web-inbox-producers/7g-bottom-bar-anyone-who-not.webp): The bottom bar of anyone who is not an admin: no People (signed in as Rui, Basic)

### Web: Settings, Devices, People, the key dialog, empty and error states

Folder `images/web-settings-people/`, 9 images.

- [8a](images/web-settings-people/8a-settings-desktop-rodrigo-admin-devices.webp): Settings on a desktop (Rodrigo, Admin): Devices, About this server, this browser
- [8b](images/web-settings-people/8b-sign-out-confirmation-settings-phone.webp): Sign out: the confirmation, and Settings at phone width (Rui, Basic)
- [8c](images/web-settings-people/8c-devices-rui-basic-browsers-carry.webp): Devices (Rui, Basic): browsers carry a globe and a "Browser" tag; revoking one
- [8c2](images/web-settings-people/8c2-devices-admin-sees-them-rodrigo.webp): Devices as an admin sees them (Rodrigo): grouped by person
- [8d](images/web-settings-people/8d-people-admins-only-rodrigo-list.webp): People, admins only (Rodrigo): list, a person open, and Invite: the form, then the QR code
- [8e](images/web-settings-people/8e-new-key-shown-once-dialog.webp): A new key, shown once: the dialog (the content of 2b), with Share when the browser has it
- [8f](images/web-settings-people/8f-empty-not-found-offline-load.webp): Empty, not found, offline and load error (phone width; the same words on a desktop)
- [8g](images/web-settings-people/8g-desktop-nothing-selected-missing-event.webp): Desktop: nothing selected, and a missing event beside the list
- [8h](images/web-settings-people/8h-address-that-not-page-example.webp): An address that is not a page (for example People for a non-admin)

### Design system: section images of the design system page

Folder `images/design-system/`, 12 images.

- [s0](images/design-system/s0-how-new-screens-decided.webp): How new screens are decided
- [s1](images/design-system/s1-color-dark-scheme.webp): Color: dark scheme
- [s2](images/design-system/s2-type-material-3-scale-roboto.webp): Type: Material 3 scale, Roboto
- [s3](images/design-system/s3-shape-space.webp): Shape and space
- [s4](images/design-system/s4-components-app-draws-them-1.webp): Components, as the app draws them (1 px = 1 dp)
- [s5](images/design-system/s5-patterns-added-users.webp): Patterns added for users
- [s6](images/design-system/s6-feedback-state-components.webp): Feedback and state components
- [s7](images/design-system/s7-accessibility-text-size-motion.webp): Accessibility, text size and motion
- [s8](images/design-system/s8-undo-or-confirm.webp): Undo or confirm
- [s9](images/design-system/s9-same-components-web-page.webp): The same components on the web page
- [s10](images/design-system/s10-contrast-checked.webp): Contrast, checked
- [s11](images/design-system/s11-patterns-keep.webp): Patterns to keep

