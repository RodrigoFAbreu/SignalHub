# SignalHub client

The SignalHub app for Android and iOS, built with Flutter from one codebase.
It sets itself up by scanning a pairing code the operator made (or with a
server address and client key typed in), registers for
push notifications, and shows the inbox: every event, newest first, and each
event's details, also opened by tapping its notification. Unread events are
marked and counted; opening one marks it read on every client of the owner,
and its screen marks it read or unread again, whichever it is not.
The filter button narrows the inbox to unread events, and to chosen
producers, categories and severities; the server applies them, a bar above
the inbox shows the active ones, and *Clear* removes them all. They last
while the app runs and are not remembered after a restart.
An event with a link offers *Open link* on its screen, which opens it in the
system browser (or the app the phone assigns to the address); the link is
never opened from the inbox or the notification, only from the event.
The *Notifications* screen chooses which events are pushed to this device.
See
[docs/architecture.md](../docs/architecture.md#client-application) for its
design and [docs/development.md](../docs/development.md#client) for the
commands that CI runs.

## Layout

| Path | Contents |
|---|---|
| `lib/main.dart` | Wiring: starts push with built-in options, or hands the controller the start from served ones; creates the controller, runs the app. |
| `lib/src/api/` | `SignalHubApi`, the client side of the backend's HTTP API. |
| `lib/src/models/` | Events, the inbox filter, the client registration and the served push options, read from API JSON. |
| `lib/src/connection/` | Server address and client key, kept in secure storage; the pairing URI. |
| `lib/src/push/push_service.dart` | `PushService`, the provider-neutral push port, and `PushNotice`. |
| `lib/src/push/push_registration.dart` | Keeps the server's push target in step with the provider's token. |
| `lib/src/push/firebase_push_service.dart` | The Firebase Cloud Messaging adapter: the only Dart code that knows Firebase. |
| `lib/src/build_identity.dart` | Which SignalHub build the app is: release version and commit, from build-time defines. |
| `lib/src/app_controller.dart` | App state and behaviour; the UI only renders it. |
| `lib/src/ui/` | The setup, pairing scanner, inbox (with its filter sheet), event, device and notifications screens; `link_opener.dart` hands an event's link to the platform (`url_launcher`). |
| `android/`, `ios/` | Platform projects: identifiers, permissions, push capability, the browsers an event's link may open in (Android `<queries>`). |
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
   *This device* screen says "SignalHub X.Y.Z" and the release's commit.

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

After setup the home screen says *Push notifications are on*, and the
client's registration (`GET /api/v1/admin/clients/{id}`) shows push target
provider `fcm`. Publish an event and it arrives as a notification; on
Android it pops up, and *Settings → Apps → SignalHub → Notifications →
Events* changes how. While the app is in the foreground, pushes appear in
its list instead of as a system notification; pushes that arrived in the
background are in the list when you return to the app. Pushes are delivered
at least once; the app lists each event once.

## Build identity

The *This device* screen (from the inbox menu) says which build the app is,
in two lines: the release and the exact source.

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
