import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:signalhub_client/src/app.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/build_identity.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/features/devices_controller.dart';
import 'package:signalhub_client/src/onboarding/onboarding_store.dart';
import 'package:signalhub_client/src/ui/pairing_scanner_screen.dart';

import 'fakes.dart';
import 'screenshot.dart';

/// A camera for tests: a placeholder region that hands codes to the setup
/// screen as the real camera would, and can turn out not to be allowed.
class FakeCamera {
  PairingScanHandlers? _handlers;

  /// How often the setup screen built the camera region.
  int builds = 0;

  Widget build(BuildContext context, PairingScanHandlers handlers) {
    _handlers = handlers;
    builds++;
    return const SizedBox(height: scannerHeight, child: Text('camera'));
  }

  /// The camera reads [code].
  void scan(String code) => _handlers!.onCode(code);

  /// The phone does not let the app use the camera.
  void deny() => _handlers!.onCameraUnavailable();
}

/// Makes the phone's clipboard hold [text] (or nothing), as the platform's
/// would.
void mockClipboard(WidgetTester tester, [String? text]) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return text == null ? null : <String, Object?>{'text': text};
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

/// The step the device keeps, as the device would across restarts.
class InMemoryOnboardingStore implements OnboardingStore {
  InMemoryOnboardingStore([this.saved]);

  OnboardingStep? saved;

  /// Whether reading or saving fails, as a platform error would.
  bool fails = false;

  @override
  Future<OnboardingStep?> load() async {
    if (fails) throw PlatformException(code: 'error');
    return saved;
  }

  @override
  Future<void> save(OnboardingStep step) async {
    if (fails) throw PlatformException(code: 'error');
    saved = step;
  }
}

/// What `GET /api/v1/client/server` answers; `null` for a server released
/// before it, which has no such path.
class FakeServerInfo {
  FakeServerInfo({this.version = '3.4.0', this.commit = 'a1b2c3d4e5f6'});

  String? version;
  String? commit;

  /// Whether the server fails with an error instead of answering.
  bool fails = false;

  /// Whether the server has no such path.
  bool missing = false;

  int reads = 0;

  /// While set, the server does not answer until it completes.
  Completer<void>? hold;

  /// Adds the path to [backend].
  void install(FakeBackend backend) {
    backend.handlers.add((request, path) async {
      if (request.method != 'GET' || path != '/api/v1/client/server') {
        return null;
      }
      reads++;
      await hold?.future;
      if (missing) return _json(404, {'title': 'Not Found', 'status': 404});
      if (fails) return _json(500, {'title': 'Server error', 'status': 500});
      return _json(200, {'version': version, 'commit': ?commit});
    });
  }
}

/// The producers this user sees, as `GET /api/v1/client/visible-producers`
/// lists them, and the subscriptions to change.
class FakeVisibleProducers {
  final producers = <Map<String, Object?>>[];

  /// Whether reading the list fails with an error.
  bool fails = false;

  int reads = 0;

  void add(
    String id,
    String name, {
    bool subscribed = true,
    String owner = 'Ana',
    String visibility = 'PUBLIC',
  }) => producers.add({
    'id': id,
    'name': name,
    'owner': {'id': 'u-$owner', 'name': owner},
    'visibility': visibility,
    'disabled': false,
    'subscribed': subscribed,
  });

  void install(FakeBackend backend) {
    backend.handlers.add((request, path) {
      // The Producers list asks for the producers this user owns with them:
      // none here.
      if (request.method == 'GET' && path == '/api/v1/client/producers') {
        return _json(200, {'items': <Object?>[]});
      }
      if (request.method != 'GET' ||
          path != '/api/v1/client/visible-producers') {
        return null;
      }
      reads++;
      if (fails) return _json(500, {'title': 'Server error', 'status': 500});
      return _json(200, {'items': producers});
    });
  }
}

http.Response _json(int status, Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// The app against an in-memory server, with a fake camera and an onboarding
/// store, for the first-run screens: a device of the role under test that is
/// set up already, or one that stops at setup. [step] is what the device
/// kept about the welcome (`null`: it kept nothing, as a device does that was
/// connected before the app did).
class FirstRunHarness {
  FirstRunHarness({
    String role = 'BASIC',
    OnboardingStep? step,
    BuildIdentity build = const BuildIdentity(),
  }) : onboardingStore = InMemoryOnboardingStore(step) {
    backend
      ..userRole = role
      ..admin = role == 'ADMIN';
    controller = AppController(
      store: store,
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: (url, code) =>
          (redeemOverride ?? backend.redeemPairing)(url, code),
      push: push,
      alertPlatform: alerts,
      build: build,
      onboarding: onboardingStore,
    );
  }

  final backend = FakeBackend();
  final push = FakePushService();
  final store = InMemoryCredentialsStore();
  final camera = FakeCamera();
  final alerts = FakeAlertPlatform();
  final InMemoryOnboardingStore onboardingStore;
  late final AppController controller;

  /// Redeems a pairing code instead of the backend, to fail in a way the
  /// backend cannot be made to.
  PairingRedeemer? redeemOverride;

  /// How often the app was asked to open the phone's settings of the app.
  int settingsOpened = 0;

  /// Opens the app. A device that is [connected] starts with credentials the
  /// server accepts; otherwise it stops at setup (and a pairing code can be
  /// redeemed: add it to `backend.pairingCodes`).
  ///
  /// With [wait] false it does not wait for the first reads, so a test can
  /// look at the app while the server holds them back.
  Future<void> start(
    WidgetTester tester, {
    bool connected = true,
    bool wait = true,
  }) async {
    if (connected) {
      store.saved = ServerCredentials.parse(serverUrl, clientKey);
    } else {
      backend.acceptedKey = null;
    }
    await tester.pumpWidget(
      RepaintBoundary(
        key: screenshotKey,
        child: SignalHubApp(
          controller: controller,
          scanner: camera.build,
          linkOpener: (link) async => true,
          settingsOpener: () async => settingsOpened++,
        ),
      ),
    );
    if (wait) {
      await tester.runAsync(controller.start);
      await settle(tester);
    } else {
      await tester.runAsync(() async {
        unawaited(controller.start());
        await pumpEventQueue();
      });
      await tester.pump();
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }
}

/// The devices feature as Settings' _Devices_ row sees it: a summary line, and
/// how often the row asked for the devices.
class FakeDevicesController extends DevicesController {
  FakeDevicesController(super.gateway, this.text);

  final String? text;
  int loads = 0;

  @override
  String? get summary => text;

  @override
  Future<void> load() async => loads++;
}

/// Holds `GET /api/v1/events` (the inbox's first page) until it completes, or
/// makes it fail with [status].
class FakeInboxGate {
  Completer<void>? hold;

  /// The status the server answers the inbox with instead of the page.
  int? status;

  void install(FakeBackend backend) {
    backend.handlers.add((request, path) async {
      if (request.method != 'GET' || path != '/api/v1/events') return null;
      await hold?.future;
      if (status case final status?) {
        return _json(status, {'title': 'Server error', 'status': status});
      }
      return null;
    });
  }
}
