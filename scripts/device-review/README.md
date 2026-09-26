# Device review

`device_review.py` drives the functional review of the SignalHub Android app
on a real phone over `adb`: it publishes events as a producer, and checks
what the phone and the server show, from start-up to pushes, read state,
push preferences and recovery from a stopped backend. It is review tooling
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
| `events-channel` | The app's `events` notification channel must be at high importance (4) or more. | Nothing. |
| `foreground-push` | Publishes with the app in front; the event must appear in the inbox, with no system notification. | Publishes 1 event. |
| `background-push` | Goes home and publishes; the notification must be in the `events` channel, and tapping it in the shade must open the event and mark it read on the server. | Publishes 1 event, marks it read. |
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

## Published events

Every run publishes about 15 events as the review's producer, and they stay
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
