# SignalHub client

The SignalHub app for Android and iOS, built with Flutter from one codebase.
It connects to the owner's SignalHub server with a client key, registers for
push notifications, and shows the inbox: every event, newest first, and each
event's details, also opened by tapping its notification. Unread events are
marked and counted; opening one marks it read on every client of the owner,
and its screen marks it read or unread again, whichever it is not.
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
| `lib/src/models/` | Events, the client registration and the served push options, read from API JSON. |
| `lib/src/connection/` | Server address and client key, kept in secure storage. |
| `lib/src/push/push_service.dart` | `PushService`, the provider-neutral push port, and `PushNotice`. |
| `lib/src/push/push_registration.dart` | Keeps the server's push target in step with the provider's token. |
| `lib/src/push/firebase_push_service.dart` | The Firebase Cloud Messaging adapter: the only Dart code that knows Firebase. |
| `lib/src/build_identity.dart` | Which SignalHub build the app is: release version and commit, from build-time defines. |
| `lib/src/app_controller.dart` | App state and behaviour; the UI only renders it. |
| `lib/src/ui/` | The setup, inbox, event, device and notifications screens. |
| `android/`, `ios/` | Platform projects: identifiers, permissions, push capability. |
| `icon/` | The app icon (`icon.svg`) and `render.sh`, which renders its PNGs for both platforms. |
| `test/` | Unit and widget tests against a fake backend and a fake push service. |

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
see [docs/development.md](../docs/development.md#dev-mode)), register a
client for this installation and enter its key in the app:

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
`SIGNALHUB_VERSION`, is set only by a release's own app build; it is not a
setting for local builds, so a build from a release's tag never claims to be
that release (see
[docs/architecture.md](../docs/architecture.md#version)). No release builds
the app yet, so every installed app is a development build.

## Icon

`icon/icon.svg` is the app icon. After changing it, run `icon/render.sh`
(needs `rsvg-convert` and ImageMagick 7) to render the iOS icons and the
Android icons for Android 7, and copy the glyph into the Android vector
drawables `ic_launcher_foreground.xml` (the adaptive and themed icons from
Android 8) and `ic_notification.xml` (the status bar icon of pushes). Commit
the results.

## Signing

SignalHub is self-hosted and not distributed through the app stores. Android
release builds are signed with the local debug key, which is enough to
install them on your own devices. iOS builds are signed in Xcode with the
owner's Apple developer team (`open ios/Runner.xcworkspace`).
