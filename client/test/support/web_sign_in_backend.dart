import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:signalhub_client/src/connection/incoming_links.dart';

import 'fakes.dart';

/// The browsers' sign-ins of the client API (`/api/v1/client/web-sign-ins`),
/// answering as docs/architecture.md describes: a lookup by the code a page
/// shows, which finds a live sign-in or answers `404`, and `429` once a device
/// has tried [triesAllowed] wrong codes; then approving or cancelling it by
/// ID. It is added to a [FakeBackend]'s `handlers`.
class WebSignInBackend {
  WebSignInBackend(this.backend) {
    backend.handlers.add(_handle);
  }

  final FakeBackend backend;

  /// How many wrong codes a device may try before it is refused.
  static const triesAllowed = 5;

  /// The scan code of the page's QR code, and the short code it shows.
  static const scanCode = 'shsc1_Qm3Zt9xKc8wYp4aLd2VbNe';
  static const shortCode = 'K7Q-4MX';

  final _live = <String, String>{};
  final _browsers = <String, String>{};

  /// The IDs of the sign-ins that were approved and cancelled, in order.
  final approved = <String>[];
  final cancelled = <String>[];

  /// Every request, as `METHOD /path`, and the codes looked up.
  final requests = <String>[];
  final lookups = <String>[];
  int wrongTries = 0;

  /// Fails approving with this status; the connection fails when it is `0`.
  int? approveFailsWith;

  /// A page waits for a sign-in with the codes [codes] (the QR code's and the
  /// short one by default), for the browser [browserName].
  void add({
    String id = 'signin-1',
    String browserName = 'Firefox on Linux',
    List<String> codes = const [scanCode, shortCode],
  }) {
    for (final code in codes) {
      _live[_normal(code)] = id;
    }
    _browsers[id] = browserName;
  }

  /// The page gave up: nothing is live any more.
  void expire() => _live.clear();

  static String _normal(String code) =>
      code.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  http.Response? _handle(http.Request request, String path) {
    if (!path.startsWith('/api/v1/client/web-sign-ins')) return null;
    requests.add('${request.method} $path');
    if (path == '/api/v1/client/web-sign-ins/lookup') {
      final code =
          (jsonDecode(request.body) as Map<String, Object?>)['code']! as String;
      lookups.add(code);
      if (wrongTries >= triesAllowed) return _json(429, 'Too many tries');
      final id = _live[_normal(code)];
      if (id == null) {
        wrongTries++;
        return _json(404, 'No sign-in');
      }
      return _json(200, {
        'id': id,
        'browserName': _browsers[id],
        'expiresAt': '2026-10-10T12:03:00Z',
      }, ok: true);
    }
    final match = RegExp(
      r'^/api/v1/client/web-sign-ins/([^/]+)/(approve|cancel)$',
    ).firstMatch(path);
    if (match == null) return _json(404, 'Not Found');
    final id = match.group(1)!;
    final approve = match.group(2) == 'approve';
    final failing = approveFailsWith;
    if (approve && failing != null) {
      if (failing == 0) throw http.ClientException('offline', request.url);
      return _json(failing, 'Failed');
    }
    if (!_live.containsValue(id)) return _json(404, 'No sign-in');
    _live.removeWhere((_, live) => live == id);
    (approve ? approved : cancelled).add(id);
    return http.Response('', 204);
  }

  static http.Response _json(int status, Object body, {bool ok = false}) =>
      http.Response(
        jsonEncode(ok ? body : {'title': body, 'status': status}),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// The links the phone opens the app with: the one it started with, and
/// those opened while it runs.
class FakeIncomingLinks implements IncomingLinks {
  FakeIncomingLinks([this.initial]);

  String? initial;
  final _opened = StreamController<String>.broadcast();

  @override
  Future<String?> initialLink() async => initial;

  @override
  Stream<String> get links => _opened.stream;

  /// The phone opens [link] while the app runs.
  void open(String link) => _opened.add(link);
}
