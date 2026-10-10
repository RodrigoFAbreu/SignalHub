# SignalHub client

The SignalHub app for Android and iOS, built with Flutter from one codebase.
It sets itself up by scanning a pairing code the operator or an admin
device made (or with a server address and client key typed in), registers for
push notifications, and shows the inbox: every event, newest first, and each
event's details, also opened by tapping its notification. Unread events are
marked and counted; opening one marks it read on every client of the owner,
and its screen marks it read or unread again, whichever it is not.
The filter button narrows the inbox to unread events, and to chosen
producers, categories and severities; the server applies them, a bar above
the inbox shows the active ones, and *Clear* removes them all. They last
while the app runs and are not remembered after a restart. With *Unread only*
on, an event that becomes read in the app (opened, marked read or *Mark all as
read*) leaves the inbox, and one marked unread again returns in its place.
An event with a link offers *Open link* on its screen, which opens it in the
system browser (or the app the phone assigns to the address); the link is
never opened from the inbox or the notification, only from the event.
A bottom bar switches between the inbox, [Producers and People](#navigation-and-roles)
and [Settings](#settings): whether and which
events are pushed to this device, how pushes sound and vibrate on Android,
with SignalHub's own sounds, which pushes sound on silent and during Do
Not Disturb, and a separate alert for critical events (see
[Alert](#alert)), the devices the role may see, [signing a browser in](#sign-in-a-browser), and
this device, from which it is disconnected.
See
[docs/architecture.md](../docs/architecture.md#client-application) for its
design and [docs/development.md](../docs/development.md#client) for the
commands that CI runs.

## Layout

| Path | Contents |
|---|---|
| `lib/main.dart` | Wiring: starts push with built-in options, or hands the controller the start from served ones; creates the controller, runs the app. |
| `lib/src/api/` | `SignalHubApi`, the client side of the backend's HTTP API. |
| `lib/src/models/` | Events, the inbox filter, the client registration, the devices an admin device lists and the served push options, read from API JSON. |
| `lib/src/connection/` | Server address and client key, kept in secure storage; the pairing URI; the sign-in link and typed code of a web page (`web_sign_in_link.dart`); the links the phone opens the app with (`incoming_links.dart`). |
| `lib/src/push/push_service.dart` | `PushService`, the provider-neutral push port, and `PushNotice`. |
| `lib/src/push/push_registration.dart` | Keeps the server's push target in step with the provider's token. |
| `lib/src/push/firebase_push_service.dart` | The Firebase Cloud Messaging adapter: the only Dart code that knows Firebase. |
| `lib/src/build_identity.dart` | Which SignalHub build the app is: release version and commit, from build-time defines. |
| `lib/src/alert/` | The alert settings (sound, volume, vibration with its pattern and length, which pushes sound on silent and during Do Not Disturb, and critical events' own), what the platform is given for them, their controller, and `AlertPlatform`, the port to the Android code that stores and plays them. |
| `lib/src/settings/` | The groups of the Settings screen, and which of them are open, kept in secure storage. |
| `lib/src/app_controller.dart` | App state and behaviour; the UI only renders it. |
| `lib/src/features/web_sign_in_controller.dart` | Signing a browser in: reading the code, the question, approving or cancelling. |
| `lib/src/ui/` | The setup, pairing scanner, *Sign in a browser* (`sign_in_browser_screen.dart`), inbox (with its filter sheet), event, Settings (with its push filters and alert sections), devices (for an admin device) and *Connect a device* (a pairing code as a QR code, drawn with the pure-Dart `qr` package) screens; `link_opener.dart` hands an event's link to the platform (`url_launcher`). |
| `android/`, `ios/` | Platform projects: identifiers, permissions, push capability, the browsers an event's link may open in (Android `<queries>`), and the `signalhub://signin` link the app opens from (Android intent filter). |
| `android/app/src/main/kotlin/` | `SignalHubApplication` (the *Events* channel), `PushAlertReceiver` and `AlertPlayer` (the alert), `MainActivity` (the alert settings' method channel, Do Not Disturb access, and the sign-in links). |
| `sounds/` | The alert sounds' generator, `generate.py`, and their source and licence; the sounds are in `android/app/src/main/res/raw/`. |
| `icon/` | The app icon (`icon.svg`) and `render.sh`, which renders its PNGs for both platforms. |
| `test/` | Unit and widget tests against a fake backend and a fake push service. |

## Install a release

Every release from v1.7.0 attaches the Android app, `SignalHub-X.Y.Z.apk`,
built from the release's commit and signed with SignalHub's release key.
It has no Firebase options of its own: after setup it reads the push
options your server serves (see [Push notifications](#push-notifications)),
so it works with any SignalHub server. There is no iOS release: iOS builds
need the owner's Apple team (see [Signing](#signing)).

1. Download the app and the checksums, and check them:

   ```sh
   version=1.2.3
   curl --fail --location --remote-name-all \
     "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/SignalHub-$version.apk" \
     "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/SHA256SUMS"
   sha256sum --check --ignore-missing SHA256SUMS
   ```

   Optionally, check that GitHub built it from the release's commit
   (`gh attestation verify SignalHub-$version.apk --repo
   RodrigoFAbreu/SignalHub`) and that it is signed with the release key:
   `apksigner verify --print-certs SignalHub-$version.apk` (from the
   Android SDK's build-tools) prints the certificate's SHA-256 digest,
   which the release notes name.
2. Install it: `adb install SignalHub-$version.apk` from a computer, or
   open the file on the phone and allow installing from that source.
3. Open it and set it up, as in [Set it up](#set-it-up). The
   *This device* group of Settings says "SignalHub X.Y.Z" and the release's commit.

**Updating** is installing the next release's APK the same way: Android
keeps the app's data, and the client key with it, because every release is
signed with the same key and has a higher `versionCode`
([docs/development.md](../docs/development.md#release-process)). The app
and the backend are parts of the same release; an app works with backends
of other releases within the
[compatibility rules](../docs/architecture.md#compatibility).

**Replacing a locally built app, once.** An app you built yourself is
signed with your machine's debug key, so Android refuses to update it with
the release's APK (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Uninstall it,
install the release's APK and set it up again: the old key was in the
uninstalled app's storage, so pair it again (and revoke the old client) or
reuse a key you kept. The same happens in the other
direction, from a release to a local build.

## Set it up

**Pairing** is the quick way. On the server's host, the operator creates a
one-time pairing code for the device, valid for 10 minutes, and shows its
URI as a QR code: in a browser on the
[admin page](../docs/architecture.md#the-admin-page)
(`http://localhost:8080/admin/`, over SSH from another computer), which
can also copy the code to send to someone, or in a terminal
([docs/development.md](../docs/development.md#pairing-a-device)):

```sh
uri=$(curl -s http://localhost:8080/api/v1/admin/pairings \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "Pixel 8"}' | jq -r .uri)
qrencode -t ansiutf8 "$uri"
```

In the app, tap **Scan pairing code** and point the camera at it (Android
and iOS ask for the camera then, and only then), or paste the URI
(`signalhub://pair?…`) under **Pairing link** and tap **Pair**. The app
registers itself as a new client with its own key, which the operator can
list and revoke like any other, and sets up push. An expired or used code
says so: create a new one. The URI names the server by its
`SIGNALHUB_PUBLIC_URL`; if the app cannot reach that address, it says so
and names it. Without `SIGNALHUB_PUBLIC_URL` a pairing has no URI: set it,
or set the app up by hand.

A mod or an admin makes the same code in the app, with **Connect a device**
in *Devices* (an admin also for anyone else, and *Invite* in *People*), so no
one needs the host.

**By hand**, under **Or set up by hand**: enter the server address and a
client key the operator registered for this device
(`POST /api/v1/admin/clients`, see [Run it](#run-it)).

## Run it

With the Flutter SDK (version in
[docs/development.md](../docs/development.md#client)) and an emulator,
simulator or device:

```sh
flutter pub get
flutter run --dart-define=SIGNALHUB_REVISION="$(git rev-parse HEAD)"
```

Without Firebase options, built in or served by the server (see
[Push notifications](#push-notifications)), the app runs without push and
says so. To connect
it, start the backend (for example `./mvnw quarkus:dev` with an admin token,
see [docs/development.md](../docs/development.md#dev-mode)) and pair the app
(see [Set it up](#set-it-up); with `SIGNALHUB_PUBLIC_URL` set to the address
below), or register a client for this installation and enter its key in the
app:

```sh
curl -s http://localhost:8080/api/v1/admin/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "Pixel emulator"}' | jq -r .clientKey
```

The server address is `http://10.0.2.2:8080` from the Android emulator and
`http://localhost:8080` from the iOS simulator. Plain HTTP works only in
Android debug builds and, on iOS, to local addresses; anything reachable from
elsewhere needs HTTPS through a reverse proxy.

## Navigation and roles

The connected app has a bottom bar: **Inbox**, **Producers**, **Settings**,
and **People** for an admin, with the unread count on *Inbox*. What a person
can do follows their role on the server (*Basic*, *Mod* or *Admin*); the app
shows what the role can do and hides what it cannot, or says who can help.
Only the host makes an admin, on the admin page. If the role changes while
the app is open, it learns of it when an action is refused or when it reads
the registration again, rebuilds the screens and says so once.

A device that connects gets a short welcome, once. A device that was
connected before an update that added new screens gets a **What's new** card
at the top of the inbox, once.

- **Producers** lists every producer you can see, under a search field and
  the chips *All*, *Yours*, *Subscribed* and *Can subscribe*. The bell
  subscribes or unsubscribes in place (with *Undo*). **New producer** names
  one and shows its key **once**: copy or share it before leaving. A
  producer's screen renames it, sets who can see it, adds people to a private
  one, lists its keys, issues and revokes keys and disables or enables it.
- **People** (admins) lists everyone in sections by role, invites someone
  with a pairing code, and shows a person's role (*Basic* or *Mod*; *Admin* is
  set on the admin page), devices and producers.
- **Devices** (Settings, every role) lists the devices your role may see: your
  own for a basic user (read only) and a mod (who connects, renames and
  revokes them), everyone's, grouped by person, for an admin (who also
  deletes revoked ones and connects a device for anyone). A browser signed in
  to a web page is listed like a device, with the globe icon and a `Browser`
  tag (`This device` marks the one in use, `Admin device` and `Revoked` the
  others). Every role signs out its own browsers: a mod
  and an admin from the row menu (*Rename*, *Sign out*) and a basic user with
  a *Sign out* button, which asks first and says the browser stops being a
  device of theirs; a signed out browser of their own can then be deleted,
  by every role. An admin's browser is not an admin device: its user changes
  it, no other admin does. A mod's last active *device* cannot be revoked;
  browsers do not count for that. A basic user's phones stay read only.

## Settings

The **Settings** tab holds every setting of the app. At the top, always
shown, the **Push notifications** switch pauses or resumes pushes to this
device (events are kept in the inbox either way). Below it, in one order for
every role: **Push filters**, **Alert**, **Devices**, **Sign in a browser**,
**About this server** and **This device**. The groups that fold show, folded, a one-line summary
of their values, such as *Normal and up · Info, Completed muted · all
producers* or *Signal · 80 % · Medium · Short, short, long · Short*. Tap a
header to unfold or fold it:

- **Push filters**: the minimum severity, and the categories and producers
  pushed, saved on the server at every change. The producers listed are the
  ones you subscribe to; a muted one that is no longer listed stays, to
  unmute it.
- **Alert**: the general alert's sound, volume, vibration, pattern and
  length, with their previews, then which pushes sound on silent and
  during Do Not Disturb (see [Alert](#alert)), and **Different alert for
  critical events** with, below it, the **Critical alert** sub-group: the
  critical alert's own sound, volume, vibration, pattern and length (see
  [Critical events](#critical-events)). While the switch is off, the
  sub-group is folded and greyed and does not open; while it is on, it
  folds like the groups, with its summary, and is remembered open or
  folded as they are. The *Alert* summary also names the silent and Do
  Not Disturb choices that are not *Off*, such as *Signal · 80 % · Medium
  · Short, short, long · Short · sounds on silent: critical*.
- **Devices** opens the devices screen (above), summing them up, such as
  *4 devices · 1 browser*.
- **About this server**: the server's address, its version and commit (from
  the server itself), who you are, this app's build, and the sentence *The
  host runs this server and can see every event on it.*
- **This device**: its name and server, its push status, its build (see
  [Build identity](#build-identity)), and **Disconnect this device**,
  which asks first. Disconnecting removes this device's push target and
  forgets the server and the client key; the alert settings and the open
  groups stay on the device.

Groups start folded; those left open are open again the next time,
across restarts, kept on the device only. While push is off, *Push
filters* and *Alert* are greyed, saying they apply once
push notifications are on; they can still be changed. With a server
released before push preferences, there is no switch and *Push filters*
says the server does not support them. Where the app plays no alert of its
own (iOS), there are no alert groups.
Pull down to read the registration, the push status and the devices again.

- **Sign in a browser** opens the scanner of [signing a browser in](#sign-in-a-browser).
  It sits beside *Devices*, not inside it, so every role reaches it.

Updating from a release with the *Notifications* and *This device* screens
keeps every setting: the push preferences stay on the server and the alert
settings on the device, as before. Updating from a release with a
top-level *Critical alert* group keeps its settings, now inside *Alert*;
if it was left open, the sub-group opens with *Alert* once critical events
have their own alert.

## Sign in a browser

The web page has no password: a browser becomes one of your devices by being
approved from a device you already have, and every role may do it. The page
shows a QR code (and, under it, a short code such as `K7Q-4MX`). In the app,
**Settings › Sign in a browser** opens the camera (asked for the first time
it is needed); point it at the code. **Type a code** takes the short code
instead: in any case, with or without the dash or spaces, and its **Continue**
stays off until it has six characters. A code that is wrong or has run out
says *That code isn't right or has run out. Check the page and try again.*
under the field and keeps it; after too many wrong codes (the server allows
five from a device in ten minutes) it says *Too many tries. Wait a few
minutes, then try again.* A code that cannot be one (it has an `I`, `L`, `O`,
`0` or `1`, which codes never have) is said the same way without asking, so
it uses up no try. A server that cannot be reached is a banner, *Can't reach
SignalHub. Check your connection and try again.*, with **Try again**.

Reading a code never signs anything in. A sheet asks **Sign in this browser?**
and names the browser and system the page's browser reports (for example
*Firefox on Linux*; the server does no place lookup). **Sign in** approves
it, and the screen says *Browser signed in* with **Done**; the browser is
then listed in *Devices*, and its sign-in lasts a fixed 30 days or until it
is signed out. **Cancel**, or dismissing the sheet, tells the page, which
says the sign-in was cancelled; the camera keeps ignoring that code while it
sees it. If the page gave up meanwhile, the app says *That sign-in has ended.
Show a new code on the page and scan it.*

The QR code and the page's **Open the app** button are the same link,
`signalhub://signin?server=<server address>&code=shsc1_...`. On Android the
app registers it (an intent filter for `signalhub://signin` on its main
activity), so opening it goes straight to the question, without the camera.
The link must name the server this app is connected to: another server's code
says *That code is for another server. This app is connected to HOST.* and
nothing is asked of either server. A link opened on an app that is not set up
yet is ignored, and a newer link replaces the screen of an older one. The
app does not register pairing links, which are scanned or pasted; iOS has
no release and registers no link scheme, so *Open the app* does nothing
there, and its scanner and typed code still work.

## Push notifications

The backend sends pushes through Firebase Cloud Messaging, which relays them
to Android devices directly and to iOS devices through APNs. Receiving them
needs the owner's own Firebase project; nothing about it is committed.

The app gets the Firebase options in one of two ways:

- **From the server** (any build without its own): the operator gives the
  backend the app's `firebase-options.json` next to the service account key
  (`SIGNALHUB_PUSH_FCM_CLIENT_OPTIONS_FILE`, see
  [docs/development.md](../docs/development.md#firebase-cloud-messaging)),
  and the app reads them with its client key after setup. So one build works
  with any SignalHub server and its owner's Firebase project. The app checks
  them before starting Firebase, and runs without push if the server serves
  none (*Push is not configured on this server*) or they are not complete
  options for this platform (*This server's push configuration does not work
  with this app*). Firebase starts once per run: after connecting to a server
  with other options, or when the operator replaces them, restart the app.
- **Built in**, with `--dart-define-from-file=firebase-options.json` (step
  5), for local and development builds; they take precedence over the
  server's.

Either way, the options are those of your own Firebase project:

1. In the [Firebase console](https://console.firebase.google.com/), use the
   project whose service account key the backend has
   (`SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE`, see
   [docs/development.md](../docs/development.md#firebase-cloud-messaging)).
2. Add an Android app with package name `io.github.rodrigofabreu.signalhub`
   and an iOS app with bundle ID `io.github.rodrigofabreu.signalhub`.
3. Copy `firebase-options.example.json` to `firebase-options.json` (git
   ignored) and fill it in from the downloaded `google-services.json` and
   `GoogleService-Info.plist`. The downloaded files themselves are not needed
   and must not be committed.
4. For iOS, upload an APNs authentication key in *Project settings → Cloud
   Messaging*, and enable the Push Notifications capability for the bundle
   ID in your Apple developer account. The app already requests it
   (`ios/Runner/Runner.entitlements`).
5. Give the file to the backend (above), or build or run with it:

   ```sh
   flutter run --dart-define-from-file=firebase-options.json \
     --dart-define=SIGNALHUB_REVISION="$(git rev-parse HEAD)"
   flutter build apk --release --dart-define-from-file=firebase-options.json \
     --dart-define=SIGNALHUB_REVISION="$(git rev-parse HEAD)"
   ```

After setup the *This device* group of Settings says *Push notifications
are on*, and the
client's registration (`GET /api/v1/admin/clients/{id}`) shows push target
provider `fcm`. Publish an event and it arrives as a notification; on
Android it pops up with SignalHub's own alert (see [Alert](#alert)), and
*Settings → Apps → SignalHub → Notifications → Events* changes how. While the app is in the foreground, pushes appear in
its list instead of as a system notification, with the same alert; pushes that arrived in the
background are in the list when you return to the app. Pushes are delivered
at least once; the app lists each event once.

## Alert

On Android, a push sounds and vibrates as set in the *Alert* group of
Settings, on this device only, whether the app is open, in the background
or closed:

- **Sound**: *Signal* (the default), *Beacon*, *Pulse*, *Glass* or
  *Urgent*, SignalHub's own sounds (see [sounds/](sounds/README.md) for their source
  and licence), or *None*. Choosing one plays it; its play button plays it
  again.
- **Volume**: from 10 % to 100 % of the phone's notification volume
  (80 % by default), played when the slider is let go.
- **Vibration**: *Off*, *Light*, *Medium* (the default) or *Strong*.
  Phones that can vibrate at different strengths vibrate softer or harder;
  others buzz shorter or longer. Choosing one vibrates it.
- **Pattern**: SignalHub's own rhythm of buzzes: *Short, short, long* (the
  default, two short buzzes and a long one), *Steady* (one long buzz),
  *Heartbeat* (a short and a longer buzz, then a pause) or *Rapid pulse*
  (quick even buzzes). Choosing one vibrates it; its vibrate button
  vibrates it again, at the chosen length.
- **Length**: *Short* (about 0.6 s, the default), *Medium* (about 2 s) or
  *Long* (about 5 s), by repeating the pattern; a steady buzz lasts that
  long. Choosing one vibrates it. On a phone without amplitude control a
  *Strong* vibration's buzzes are longer, so it lasts up to about 8.5 s,
  never more than 10 s.

Pattern and length apply at every strength and are greyed while the
vibration is *Off*. Opening the notification or the app stops a vibration
still going.

Each change is saved on the phone at once and applies to the next push;
the server never sees it. The settings survive app updates, and stay when
the device disconnects. A push while the app is open plays the same alert,
under the same rules, and appears in the inbox, with no system
notification. The app's push receiver plays every push's alert, the app
open or not, and the app itself never plays one, so a push plays it once.

Unless chosen otherwise below, the phone still decides: during Do Not
Disturb the alert neither sounds nor vibrates, on silent mode likewise, on
vibrate it only vibrates, and it follows the phone's notification volume
and vibration settings. Turning the *Events* category off or to *Silent*
in *Settings → Apps → SignalHub → Notifications* silences it too, whatever
is chosen below. Another app's notifications are never affected.

### Silent mode and Do Not Disturb

Two choices in the *Alert* group, below the general alert, say which
pushes sound anyway, each with three options: *Off*, *Critical only*
(pushes of events with `CRITICAL` severity, whether or not they have a
[different alert](#critical-events)) or *All pushes* (every SignalHub
push):

- **Sound when the phone is on silent**, *Critical only* by default:
  those pushes sound and vibrate even when the phone's ringer is on silent
  or vibrate.
- **Sound during Do Not Disturb**, *Off* by default: those pushes sound
  and vibrate during Do Not Disturb. Android lets an app do that only once
  you give it *Do Not Disturb access*: choosing *Critical only* or *All
  pushes* without it opens the phone's screen to give it, and the choice
  stays *Off* until you have allowed SignalHub there and choose again.
  Taking the access away shows it *Off* until the access is given again.
  A Do Not Disturb that silences alarms too (*total silence*) still keeps
  it quiet.

A push that sounds through silent mode, vibrate or Do Not Disturb plays as
an alarm: its volume is then relative to the phone's alarm volume, not the
notification volume. Otherwise it plays like any push. The app never
changes the phone's ringer or Do Not Disturb. Previews follow the same
choices: a preview of the general alert as a normal push, of the critical
alert's own as a critical push.

After updating from a release where these were two switches for critical
events, a switch that was on becomes *Critical only* and one that was off
*Off*; the defaults are the same as before, so nothing changes until you
choose *All pushes*.

How it works: Android fixes a notification channel's sound and vibration
when the channel is created, and has no volume per channel, so the
*Events* channel makes no sound and does not vibrate, and the app plays the
alert itself when a push arrives (`PushAlertReceiver`, `AlertPlayer`),
choosing the critical alert from the push data's `severity`; see
[docs/architecture.md](../docs/architecture.md#client-application).

**Updating from an earlier release** replaces the app's notification
channel once: the old *Events* channel (`events`) is deleted and a new
*Events* channel (`signalhub_events`) takes its place, still popping up.
Any changes you made to the old channel in the phone's settings (its
sound, vibration or importance) are not carried over; set them again on
the new one if you still want them. The system settings may mention a
deleted category.

iOS is not covered: iOS plays the system's default sound, as before, for
critical events too.

### Critical events

A push of an event with `CRITICAL` severity, whatever its producer,
category or text, can alert differently, set at the end of the *Alert*
group of Settings:

- **Different alert for critical events**, off by default. Off, critical
  pushes play the general alert above, and the **Critical alert**
  sub-group below the switch is greyed and does not open. On, they play
  their own **Sound**, **Volume**, **Vibration**, **Pattern** and
  **Length**, set in that sub-group as the general ones (the same sounds,
  steps, patterns and lengths), by default *Urgent* at 100 % with a
  strong, long *Rapid pulse* vibration. Every other severity keeps the
  general alert, and so does a severity this app does not know. Turned
  off, the critical alert's own settings are kept for the next time.

Whether critical pushes sound on silent and during Do Not Disturb is
chosen [above](#silent-mode-and-do-not-disturb), for them with or without
a different alert. Turning SignalHub's notifications or the *Events*
category off or to *Silent* still silences critical pushes too.

After updating from a release without critical alerts, a critical push
plays the general alert, as before, until the app is opened once.

After updating from a release without vibration patterns and lengths, every
other setting is kept, and the pattern and length start at their defaults:
the general alert vibrates as before, and a critical push with a different
alert takes its new default (a long *Rapid pulse*) once the app is opened
once; until then it vibrates as before.

## Build identity

The *This device* group of Settings says which build the app is, in two
lines: the release and the exact source.

| Build | Shows |
|---|---|
| Built by a SignalHub release as its app | "SignalHub X.Y.Z" and "Commit <first 7 characters>" |
| Any other build, including one from a release's tag | "SignalHub development build" and "Commit <first 7 characters>" |
| Built without its commit (a plain `flutter run`) | "SignalHub development build" and "Commit unknown" |

Both come in at build time as `--dart-define`s, never from the placeholder
`version:` in `pubspec.yaml`. The commands above pass the commit,
`SIGNALHUB_REVISION` (`git rev-parse HEAD`). The version,
`SIGNALHUB_VERSION`, is set only by a release's own app build
(`scripts/release/app_files.py`); it is not a setting for local builds, so
a build from a release's tag never claims to be that release (see
[docs/architecture.md](../docs/architecture.md#version)). Releases up to
v1.6.0 attach no app, so an app from before v1.7.0 is a development build.

## Icon

`icon/icon.svg` is the app icon. After changing it, run `icon/render.sh`
(needs `rsvg-convert` and ImageMagick 7) to render the iOS icons and the
Android icons for Android 7, and copy the glyph into the Android vector
drawables `ic_launcher_foreground.xml` (the adaptive and themed icons from
Android 8) and `ic_notification.xml` (the status bar icon of pushes). Commit
the results.

## Signing

SignalHub is self-hosted and not distributed through the app stores.

- **Official Android apps**, the APKs attached to releases, are all signed
  with one release key, SignalHub's (decision D6). Only the release
  workflow uses it: it rebuilds the keystore from the repository's secrets
  inside its `app` job, which removes it at its end, and passes it to
  Gradle through `ANDROID_RELEASE_KEYSTORE`, `ANDROID_RELEASE_KEYSTORE_PASSWORD`,
  `ANDROID_RELEASE_KEY_ALIAS` and `ANDROID_RELEASE_KEY_PASSWORD`
  ([docs/development.md](../docs/development.md#repository-settings-github)).
  The keystore and its passwords are never committed, printed or uploaded;
  the maintainer keeps an offline backup.
- **Losing the release key** means no later APK can update the official
  installs: Android accepts an update only from the key that signed the
  installed app. Every device would then uninstall the app and set it up
  again with a client key, as when
  [replacing a locally built app](#install-a-release). A leaked key must be
  replaced the same way, since anyone holding it can sign updates.
- **Local Android builds**, debug or `flutter build apk --release`, are
  signed with your machine's debug key when those variables are not set,
  which is enough to install them on your own devices; they call themselves
  development builds.
- **iOS builds** are signed in Xcode with the owner's Apple developer team
  (`open ios/Runner.xcworkspace`).
