# SignalHub client

The SignalHub app for Android and iOS, built with Flutter from one codebase.
It connects to the owner's SignalHub server with a client key, registers for
push notifications, and shows the inbox: every event, newest first, and each
event's details, also opened by tapping its notification. Unread events are
marked and counted; opening one marks it read on every client of the owner.
The *Notifications* screen chooses which events are pushed to this device.
See
[docs/architecture.md](../docs/architecture.md#client-application) for its
design and [docs/development.md](../docs/development.md#client) for the
commands that CI runs.

## Layout

| Path | Contents |
|---|---|
| `lib/main.dart` | Wiring: starts push, creates the controller, runs the app. |
| `lib/src/api/` | `SignalHubApi`, the client side of the backend's HTTP API. |
| `lib/src/models/` | Events and the client registration, read from API JSON. |
| `lib/src/connection/` | Server address and client key, kept in secure storage. |
| `lib/src/push/push_service.dart` | `PushService`, the provider-neutral push port, and `PushNotice`. |
| `lib/src/push/push_registration.dart` | Keeps the server's push target in step with the provider's token. |
| `lib/src/push/firebase_push_service.dart` | The Firebase Cloud Messaging adapter: the only Dart code that knows Firebase. |
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
flutter run
```

Without Firebase options the app runs without push and says so. To connect
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
5. Build or run with the options:

   ```sh
   flutter run --dart-define-from-file=firebase-options.json
   flutter build apk --release --dart-define-from-file=firebase-options.json
   ```

After setup the home screen says *Push notifications are on*, and the
client's registration (`GET /api/v1/admin/clients/{id}`) shows push target
provider `fcm`. Publish an event and it arrives as a notification. While the
app is in the foreground, pushes appear in its list instead of as a system
notification. Pushes are delivered at least once; the app lists each event
once.

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
