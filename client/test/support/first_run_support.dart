import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:signalhub_client/src/onboarding/onboarding_store.dart';
import 'package:signalhub_client/src/ui/pairing_scanner_screen.dart';

import 'fakes.dart';

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

  /// Adds the path to [backend].
  void install(FakeBackend backend) {
    backend.handlers.add((request, path) {
      if (request.method != 'GET' || path != '/api/v1/client/server') {
        return null;
      }
      reads++;
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
