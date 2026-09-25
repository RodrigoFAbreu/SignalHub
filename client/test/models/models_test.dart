import 'package:flutter_test/flutter_test.dart';
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
}
