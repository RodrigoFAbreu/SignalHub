import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/connection/pairing_uri.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/client_registration.dart';
import 'package:signalhub_client/src/models/event.dart';

void main() {
  group('Event', () {
    Map<String, Object?> json({String category = 'INFO'}) => {
      'id': 'e-1',
      'producer': {'id': 'p-1', 'name': 'backup-job'},
      'context': 'nas',
      'category': category,
      'severity': 'CRITICAL',
      'title': 'Disk full',
      'message': 'Only 1% left.',
      'metadata': {
        'volume': '/data',
        'nested': {'a': 1},
      },
      'occurredAt': '2026-09-25T12:00:00Z',
      'createdAt': '2026-09-25T12:00:01.5Z',
      'readAt': '2026-09-25T12:05:00Z',
    };

    test('reads every documented field', () {
      final event = Event.fromJson(json());

      expect(event.producer.id, 'p-1');
      expect(event.context, 'nas');
      expect(event.category, EventCategory.info);
      expect(event.severity, EventSeverity.critical);
      expect(event.message, 'Only 1% left.');
      expect(event.metadata['nested'], {'a': 1});
      expect(event.occurredAt, DateTime.utc(2026, 9, 25, 12));
      expect(event.createdAt, DateTime.utc(2026, 9, 25, 12, 0, 1, 500));
    });

    test('is unread without readAt, and can change locally', () {
      final read = Event.fromJson(json());
      expect(read.readAt, DateTime.utc(2026, 9, 25, 12, 5));
      expect(read.isRead, isTrue);

      final unread = Event.fromJson({...json(), 'readAt': null});
      expect(unread.isRead, isFalse);

      final marked = unread.withReadAt(DateTime.utc(2026, 9, 26));
      expect(marked.isRead, isTrue);
      expect(marked.id, unread.id);
      expect(marked.title, unread.title);
      expect(marked.metadata, unread.metadata);
    });

    test('reads its link', () {
      final event = Event.fromJson({
        ...json(),
        'link': 'https://ci.example.com/runs/1842?attempt=2#log',
      });

      expect(
        event.link,
        Uri.parse('https://ci.example.com/runs/1842?attempt=2#log'),
      );
      expect(Event.fromJson(json()).link, isNull);
      expect(Event.fromJson({...json(), 'link': null}).link, isNull);
      expect(event.withReadAt(null).link, event.link);
    });

    test('accepts the links the server accepts', () {
      for (final link in [
        'http://intranet.example/status',
        'HTTPS://Example.ORG/Path',
        'https://ci.example.com:8443/runs/1',
      ]) {
        expect(parseLink(link), isNotNull, reason: link);
      }
    });

    test('ignores a link it cannot open, and keeps the event', () {
      for (final link in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'intent://scan/#Intent;scheme=zxing;end',
        'mailto:owner@example.org',
        'ftp://files.example.org/a',
        '/runs/1842',
        'ci.example.com/runs/1842',
        'https://',
        'https:///runs/1842',
        'http://[::1',
        '',
        42,
        {'url': 'https://example.org'},
      ]) {
        final event = Event.fromJson({...json(), 'link': link});
        expect(event.link, isNull, reason: '$link');
        expect(event.title, 'Disk full');
      }
    });

    test('keeps events with a category added in a later release', () {
      final event = Event.fromJson(json(category: 'SOMETHING_NEW'));

      expect(event.category, EventCategory.unknown);
      expect(event.title, 'Disk full');
    });

    test('rejects a body that breaks the contract, naming the field', () {
      expect(
        () => Event.fromJson({...json(), 'title': 42}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('"title"'),
          ),
        ),
      );
    });

    test('maps every documented category and severity', () {
      for (final name in ['ACTION_REQUIRED', 'BLOCKED', 'COMPLETED', 'INFO']) {
        expect(EventCategory.parse(name).wireName, name);
      }
      for (final name in ['LOW', 'NORMAL', 'HIGH', 'CRITICAL']) {
        expect(EventSeverity.parse(name).wireName, name);
      }
      expect(EventSeverity.parse(''), EventSeverity.unknown);
    });
  });

  test('ClientRegistration reads its push target', () {
    final client = ClientRegistration.fromJson({
      'id': 'c-1',
      'name': 'Phone',
      'createdAt': '2026-09-25T12:00:00Z',
      'revokedAt': null,
      'pushTarget': {'provider': 'fcm', 'updatedAt': '2026-09-25T12:05:00Z'},
    });

    expect(client.pushTarget?.provider, 'fcm');
    expect(client.revokedAt, isNull);
  });

  group('PushPreferences', () {
    Map<String, Object?> client(Object? preferences) => {
      'id': 'c-1',
      'name': 'Phone',
      'createdAt': '2026-09-25T12:00:00Z',
      'revokedAt': null,
      'pushTarget': null,
      'pushPreferences': preferences,
    };

    test('are read from the registration', () {
      final preferences = ClientRegistration.fromJson(
        client({
          'enabled': false,
          'minimumSeverity': 'NORMAL',
          'mutedCategories': ['COMPLETED', 'INFO'],
          'mutedProducerIds': ['p-1'],
        }),
      ).pushPreferences!;

      expect(preferences.enabled, isFalse);
      expect(preferences.minimumSeverity, 'NORMAL');
      expect(preferences.mutedCategories, ['COMPLETED', 'INFO']);
      expect(preferences.mutedProducerIds, ['p-1']);
    });

    test('are absent from a server without them', () {
      final json = client(null)..remove('pushPreferences');

      expect(ClientRegistration.fromJson(json).pushPreferences, isNull);
    });

    test('keep values added in a later release when changed', () {
      final preferences = PushPreferences.fromJson({
        'enabled': true,
        'minimumSeverity': 'URGENT',
        'mutedCategories': ['DIGEST'],
        'mutedProducerIds': <String>[],
      });

      expect(preferences.copyWith(enabled: false).toJson(), {
        'enabled': false,
        'minimumSeverity': 'URGENT',
        'mutedCategories': ['DIGEST'],
        'mutedProducerIds': <String>[],
      });
    });

    test('reject a list that breaks the contract, naming the field', () {
      expect(
        () => PushPreferences.fromJson({
          'enabled': true,
          'minimumSeverity': 'LOW',
          'mutedCategories': [1],
          'mutedProducerIds': <String>[],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('mutedCategories'),
          ),
        ),
      );
    });
  });

  group('ServerCredentials', () {
    const key = 'shck1_abc_secret';

    test('trims input and drops trailing slashes', () {
      final c = ServerCredentials.parse(
        ' https://example.org/hub// ',
        ' $key ',
      );

      expect(c.baseUrl, 'https://example.org/hub');
      expect(c.clientKey, key);
      expect(
        c.endpoint('api/v1/client').toString(),
        'https://example.org/hub/api/v1/client',
      );
    });

    test('accepts http for local development', () {
      expect(
        ServerCredentials.parse('http://10.0.2.2:8080', key).baseUrl,
        'http://10.0.2.2:8080',
      );
    });

    for (final url in [
      '',
      'signalhub.example.org',
      'ftp://example.org',
      'https://',
      'https://example.org?x=1',
    ]) {
      test('rejects the server address "$url"', () {
        expect(() => ServerCredentials.parse(url, key), throwsFormatException);
      });
    }

    test('rejects a producer key', () {
      expect(
        () => ServerCredentials.parse('https://example.org', 'shpk1_abc_x'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('shck1_'),
          ),
        ),
      );
    });

    test('never shows the key in toString', () {
      expect(
        ServerCredentials.parse('https://example.org', key).toString(),
        isNot(contains('secret')),
      );
    });
  });

  group('PairingUri', () {
    const code = 'shpc1_Zt1vQ3x9rB2mKc8wYp4aLd';

    test('reads the server and the code the backend put in it', () {
      final pairing = PairingUri.parse(
        ' signalhub://pair?server=https%3A%2F%2Fexample.org%2Fhub%2F'
        '&code=$code ',
      );

      expect(pairing.serverUrl, 'https://example.org/hub');
      expect(pairing.code, code);
    });

    for (final text in [
      '',
      code,
      'https://example.org/api/v1/pairing?code=$code',
      'signalhub://other?server=https%3A%2F%2Fexample.org&code=$code',
      'signalhub://pair?code=$code',
      'signalhub://pair?server=example.org&code=$code',
      'signalhub://pair?server=https%3A%2F%2Fexample.org',
      'signalhub://pair?server=https%3A%2F%2Fexample.org&code=shck1_abc_x',
    ]) {
      test('rejects "$text"', () {
        expect(
          () => PairingUri.parse(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              PairingUri.invalid,
            ),
          ),
        );
      });
    }

    test('never shows the code in toString', () {
      expect(
        PairingUri.parse(
          'signalhub://pair?server=https%3A%2F%2Fexample.org&code=$code',
        ).toString(),
        isNot(contains(code)),
      );
    });
  });
}
