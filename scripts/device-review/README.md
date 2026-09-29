# Device review

`device_review.py` drives the functional review of the SignalHub Android app
on a real phone over `adb`: it publishes events as a producer, and checks
what the phone and the server show, from start-up to pushes, read state,
push preferences, the app's own alert and recovery from a stopped backend. It is review tooling
for the maintainer, never part of the product, and it is not run in CI: CI
runs only its unit tests (see [Tests](#tests)).

It writes nothing into the repository. Everything specific to one machine
or device (the phone's serial, the server's address, keys, IDs and the
output directory) comes from the environment or the command line, and keys
and the admin token are read from files, never passed on a command line.

## Prerequisites

- A **debug build** of the app on the phone (`flutter run` or
  `flutter install` in `client/`), built with the Firebase options of your
  project (see [client/README.md](../../client/README.md)) and **already set
  up with a client key**, so it opens on its inbox.
- **`adb`** from the Android SDK platform tools, with the phone connected,
  USB debugging allowed, and `adb devices` listing it. Android 11 or later
  (the offline check uses `cmd connectivity airplane-mode`).
- **`adb reverse`** so the app reaches the computer's stack as the setup
  screen was told, for example `adb reverse tcp:8080 tcp:8080` for
  `http://localhost:8080`. It stays up in airplane mode, since it runs over
  USB.
- **The local Compose stack with FCM enabled**, from the repository root
  (see [docs/development.md](../../docs/development.md#firebase-cloud-messaging)).
  The script stops, starts and restarts its backend service with
  `docker compose`.
- **ImageMagick** (`compare`) for the screenshot check of the pop-up.
- **Python 3.10** or later; the script uses only the standard library.
- A **producer** for the review, for example named `device-review`, and its
  API key in a file; the app's **client ID** and **client key** in a file;
  the **admin token** in a file. Keep these files outside the repository,
  readable only by you (`chmod 600`).

## Usage

```sh
export ANDROID_SERIAL=<serial from adb devices>
export SIGNALHUB_URL=http://localhost:8080          # the stack, as this computer reaches it
export SIGNALHUB_PRODUCER_KEY_FILE=<file with the producer API key>
export SIGNALHUB_CLIENT_KEY_FILE=<file with the app's client key>
export SIGNALHUB_CLIENT_ID=<the app's client ID>
export SIGNALHUB_ADMIN_TOKEN_FILE=<file with the admin token>
export SIGNALHUB_REVIEW_OUTPUT=<directory for the results>
export SIGNALHUB_COMPOSE_DIR=<the repository root, where compose.yaml is>

python scripts/device-review/device_review.py --list          # the checks
python scripts/device-review/device_review.py                 # all of them, in order
python scripts/device-review/device_review.py --check read-state --check backend-log
```

Each option has an argument of the same meaning (`--help`); an argument
wins over the environment. There are no defaults for any of them except
`--compose-dir` (the current directory) and `--compose-service`
(`backend`, the service in `compose.yaml`).

It prints `PASS`, `FAIL` or `ABORT` for each check, and writes
`results.json`, the screenshots the checks take, one of the screen for each
failed check, and `backend.log` (from the `backend-log` check) to the
output directory. It exits with status 0 only when every selected check
passed.

## The safety guard

The script touches the screen only through taps and swipes it makes with
`input`, and before every one it reads the focused window
(`dumpsys window`). It refuses to touch the screen, and stops the whole run
(`ABORT`), unless SignalHub is in front, or the notification shade while a
check has opened it to tap a notification. A permission dialog, another
app, the lock screen or anything else in front stops it, so a run never
taps into something it did not expect. The lock screen is focused under the
same window name as the shade (`NotificationShade`), so the guard also reads
whether it is showing (`isKeyguardShowing`) and never touches a locked phone,
even while a check has opened the shade. Keys (home, back) and `am`
commands are not touches and are not guarded. Unlock the phone before a run,
and keep it from locking during one (for example *Stay awake* in the
developer options while it charges).

## Checks

Checks run in this order; each starts from the app's inbox where it needs
it. Titles of the events they publish start with `Device review:`.

| Check | What it does | What it changes |
|---|---|---|
| `connected-start` | Force-stops and starts the app; it must open on the inbox, not the setup screen, with the server's unread count on its badge. | Stops the app. |
| `device-push-on` | Opens *This device*; it must say *Push notifications are on*. | Nothing. |
| `server-push-target` | Reads the client with the admin token; its push target must be `fcm`. | Nothing. |
| `events-channel` | The app's `signalhub_events` notification channel must be at high importance (4) or more, with no sound and no vibration of its own (the app plays its alert). | Nothing. |
| `foreground-push` | Publishes with the app in front; the event must appear in the inbox, with no system notification. | Publishes 1 event. |
| `background-push` | Goes home and publishes; the notification must be in the `signalhub_events` channel, and tapping it in the shade must open the event and mark it read on the server. | Publishes 1 event, marks it read. |
| `alert-played` | Goes home and publishes; the app must log that it played its alert (`SignalHubAlert` in `logcat`) with the chosen sound. Then chooses another sound on the *Notifications* screen (which previews it), publishes again, and the app must play that one; the first sound is chosen again afterwards, even when the check fails. **What only the owner can judge:** see [Alert, by ear and by hand](#alert-by-ear-and-by-hand). | Publishes 2 events; plays the alert and two previews; restores the sound. |
| `alert-quiet` | Posts a notification as another app (`cmd notification post`, the shell's): the app must log no alert. Then **turns do-not-disturb on** (`cmd notification set_dnd priority`) and publishes with the app in the background: the app must log that it did not play its alert because of do-not-disturb. Do-not-disturb is turned off even when the check fails. | Posts a shell notification (dismiss it by hand); toggles do-not-disturb; publishes 1 event. |
| `alert-critical` | Needs the critical settings at their defaults (no different alert, *Urgent* as its own sound) and a general sound other than *Urgent*. Publishes a `NORMAL` and a `CRITICAL` event with the app in the background: the critical push must log `Critical alert played` with the normal push's sound. Then turns **Different alert for critical events** on (on the *Notifications* screen, scrolling to it), publishes a `CRITICAL` event, which must play *Urgent*, and a `NORMAL` one, which must play the general sound. The switch is turned off again, even when the check fails. | Publishes 4 events; plays the alerts; toggles the switch and restores it. |
| `alert-critical-quiet` | Needs the critical settings at their defaults. **Sets the ringer to silent** (`cmd audio set-ringer-mode SILENT`, which not every Android version has: the check then fails saying so, and silent mode is left to the list below) and publishes a `NORMAL` event, which must not play (`silent mode`), and a `CRITICAL` one, which must play as an alarm (**it sounds, at the alarm volume**). Sets the ringer back to normal, then **turns do-not-disturb on** and publishes a `CRITICAL` event, which must not play (`do not disturb`). The ringer is set to normal and do-not-disturb turned off even when the check fails. | Sets the ringer to silent, then normal (not to what it was); toggles do-not-disturb; publishes 3 events; sounds one critical alert. |
| `refresh-on-return` | Goes home, publishes, and returns; the inbox must show the event without a pull to refresh. | Publishes 1 event (`LOW`). |
| `killed-app-push` | Kills the app in the background (`am kill`, as the system would), publishes; the notification must arrive and tapping it must cold-start the app on the event. | Kills the app, publishes 1 event, marks it read. |
| `force-stop-reregisters` | Force-stops and starts the app; the server's push target must be set again (a newer `updatedAt`). | Stops the app. |
| `read-state` | Publishes, opens the event from the inbox (the server must say read), taps *Mark as unread* (the server must say unread, and the badge follow), then marks it read on the server; the badge must follow after a refresh. | Publishes 1 event (`LOW`), changes its read state. |
| `push-preferences` | Switches push off on the *Notifications* screen (the server must store it) and publishes: no notification, waiting 20 s before changing the preferences again, since they apply when the event is dispatched, not when it is published; then sets a minimum severity of `HIGH` through the API and publishes a `LOW` and a `HIGH` event: only the `HIGH` one is pushed. The preferences as they were before are restored, even when the check fails. | Publishes 3 events; restores the preferences. |
| `idempotent-publish` | Publishes twice with one idempotency key; both answers must be one event, with one notification. | Publishes 1 event. |
| `backend-down` | Publishes and shows the event, **stops the backend**, refreshes (the app must stay up), opens the event (marking it read fails, so it must offer *Mark as read*), **starts the backend**, and taps *Mark as read*: the server must say read. The backend is started again even when the check fails. | Stops and starts the backend; publishes 1 event (`LOW`). |
| `offline-push` | **Turns airplane mode on**, publishes, and expects no notification; turns it off, and the notification must arrive within 3 minutes. Airplane mode is turned off even when the check fails. | Toggles airplane mode; publishes 1 event. |
| `popup-over-other-app` | Opens the system Settings, waits 20 s for any earlier pop-up to go, publishes, and compares screenshots of the top of the screen with one taken before, from the publish on for up to 30 s (a pop-up shows for a few seconds only), with ImageMagick: a pop-up must show over Settings. Samsung's compact *brief* pop-up counts. Nothing is tapped. | Opens Settings; publishes 1 event. |
| `backend-restart` | **Restarts the backend**, then publishes: the push and the inbox must work. | Restarts the backend; publishes 1 event. |
| `no-focus-border` | On the inbox, no element may have keyboard focus; the screenshot `inbox.png` is kept for a look. | Nothing. |
| `backend-log` | The backend's log since the run started (`docker compose logs`) must have no line at `WARN` or `ERROR`, in the text or the JSON format. `backend-down` and `backend-restart` may cause some on purpose; run this check alone afterwards to look at the rest. | Nothing. |

The screen's texts the script looks for (*Show menu*, *This device*,
*Mark as read*, and so on) come from `client/lib/src/ui/`. If the app's
wording changes, update the constants at the top of the script.

## Alert, by ear and by hand

The `alert-played`, `alert-quiet`, `alert-critical` and
`alert-critical-quiet` checks read what the app says it did;
whether it sounds and feels right needs the owner. With the release APK
installed over the previous release (so the settings and the channel change
as an update makes them), check by hand:

1. After the update, before opening the app, a push plays the *Signal*
   sound with a medium vibration of two short buzzes and a long one, and
   *Settings → Apps → SignalHub → Notifications* shows the *Events*
   category, with no sound of its own.
2. On *Notifications → Alert*, each sound plays when chosen or with its
   play button; *None* plays nothing and turns the volume off.
3. With the app in the background, and again after swiping it away, a push
   plays the chosen sound at the chosen volume: 10 % is clearly quieter
   than 100 %, and both follow the phone's notification volume.
4. *Light*, *Medium* and *Strong* vibrate noticeably differently (in
   strength, or on a phone without amplitude control in length), and *Off*
   does not vibrate.
5. Changing a setting changes the next push; a push while the app is open
   plays nothing and shows in the inbox.
6. On silent mode a push is silent and does not vibrate; on vibrate it
   only vibrates; during Do Not Disturb it neither sounds nor vibrates; with
   the *Events* category set to *Silent* in the phone's settings, no alert.
7. Another app's notification still sounds as before, never like
   SignalHub's.

Critical events (publish them with `severity` `CRITICAL`, the others with
`NORMAL`, the app in the background) need the owner's phone too:

8. With the default settings (**Different alert for critical events**
   off), a `CRITICAL` and a `NORMAL` push play the same general alert.
9. With the switch on, a `CRITICAL` push plays its own sound, volume and
   vibration (by default *Urgent*, at 100 %, strong), clearly more urgent
   than the general alert, and a `NORMAL` push still plays the general
   alert; the critical sounds, volume slider and vibration play when
   chosen, as the general ones do. Off again, both play the general alert,
   and the critical settings chosen are still there when it is turned on.
10. With the default settings, on silent and on vibrate, a `CRITICAL` push
    sounds (at the phone's alarm volume) and vibrates, and a `NORMAL` push
    is silent (only vibrating on vibrate). With **Sound when the phone is
    on silent** off, the `CRITICAL` push is like the `NORMAL` one.
11. With the default settings, during Do Not Disturb, neither a
    `CRITICAL` nor a `NORMAL` push sounds or vibrates. Turning **Sound
    during Do Not Disturb** on without Do Not Disturb access opens the
    system screen that gives it and leaves the switch off; once SignalHub
    is allowed there and the app is back in front, the switch turns on, and
    a `CRITICAL` push then sounds and vibrates during Do Not Disturb (one
    that lets alarms through, Android's default) while a `NORMAL` one stays
    quiet. Taking the access away again turns the switch off and keeps
    critical pushes quiet during Do Not Disturb.

## Published events

Every run publishes about 25 events as the review's producer, and they stay
in the inbox of every client. On a local stack, delete them afterwards with
the producer's name, as described in
[Clearing local test data](../../docs/development.md#clearing-local-test-data).

## Tests

The parts that need no device are unit tested with samples recorded from
`dumpsys`, `uiautomator` and the backend log in `samples/`: the focused
window, the guard's decision (and that a refused touch sends nothing),
notification channels and posted notifications, the screen's elements and
the unread badge, log levels, and the configuration (no machine-specific
defaults, keys from files only). CI runs them, and `ruff` lints the script
with the rest of the repository:

```sh
python -m unittest discover --start-directory scripts/device-review --verbose
```
