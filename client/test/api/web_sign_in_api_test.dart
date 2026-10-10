import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';

import '../support/fakes.dart';

/// The calls that sign a browser in, each against the path and body the
/// backend documents (docs/architecture.md, "Signing in a browser").
void main() {
  final requests = <http.Request>[];
  var status = 200;
  Object answer = const <String, Object?>{};

  late SignalHubApi api;

  setUp(() {
    requests.clear();
    status = 200;
    answer = const <String, Object?>{};
    api = SignalHubApi(
      ServerCredentials.parse(serverUrl, clientKey),
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          status == 204 ? '' : jsonEncode(answer),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  String call() => '${requests.last.method} ${requests.last.url.path}';

  test('looks a code up with the client key, and reads the browser', () async {
    answer = {
      'id': 'signin-1',
      'browserName': 'Firefox on Linux',
      'expiresAt': '2026-10-10T12:03:00Z',
    };

    final found = await api.lookupWebSignIn('K7Q-4MX');

    expect(call(), 'POST /api/v1/client/web-sign-ins/lookup');
    expect(jsonDecode(requests.last.body), {'code': 'K7Q-4MX'});
    expect(requests.last.headers['Authorization'], 'Bearer $clientKey');
    expect(found.id, 'signin-1');
    expect(found.browserName, 'Firefox on Linux');
    expect(found.expiresAt, DateTime.utc(2026, 10, 10, 12, 3));
  });

  test('sends a scanned code as it was read', () async {
    answer = {
      'id': 'signin-1',
      'browserName': 'Firefox on Linux',
      'expiresAt': '2026-10-10T12:03:00Z',
    };

    await api.lookupWebSignIn('shsc1_Qm3Zt9xKc8wYp4aLd2VbNe');

    expect(jsonDecode(requests.last.body), {
      'code': 'shsc1_Qm3Zt9xKc8wYp4aLd2VbNe',
    });
  });

  for (final wrong in [404, 429]) {
    test('a lookup the server answers $wrong with that status', () async {
      status = wrong;
      answer = {'title': 'No', 'status': wrong};

      await expectLater(
        api.lookupWebSignIn('K7Q-4MY'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', wrong),
        ),
      );
    });
  }

  test('an answer without a browser is not understood', () async {
    answer = {'id': 'signin-1'};

    await expectLater(
      api.lookupWebSignIn('K7Q-4MX'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'message',
          'The server sent an unexpected answer',
        ),
      ),
    );
  });

  test('approves and cancels by ID, with no body', () async {
    status = 204;

    await api.approveWebSignIn('signin-1');
    expect(call(), 'POST /api/v1/client/web-sign-ins/signin-1/approve');
    expect(requests.last.body, isEmpty);

    await api.cancelWebSignIn('signin-1');
    expect(call(), 'POST /api/v1/client/web-sign-ins/signin-1/cancel');
    expect(requests.last.body, isEmpty);
  });

  test('a device the server no longer accepts is signed out', () async {
    status = 401;

    await expectLater(
      api.lookupWebSignIn('K7Q-4MX'),
      throwsA(isA<UnauthorizedException>()),
    );
  });
}
