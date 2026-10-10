import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/api/signalhub_api.dart';
import 'package:signalhub_client/src/api_gateway.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/models/users.dart';

import 'support/fakes.dart';

/// The user's role, the tabs it gives, and the gateway the screens' calls go
/// through.
void main() {
  late FakeBackend backend;
  late InMemoryCredentialsStore store;

  setUp(() {
    backend = FakeBackend();
    store = InMemoryCredentialsStore();
  });

  Future<AppController> connected({String role = 'BASIC'}) async {
    backend
      ..userRole = role
      ..admin = role == 'ADMIN';
    store.saved = ServerCredentials.parse(serverUrl, clientKey);
    final app = AppController(
      store: store,
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
      push: FakePushService(),
    );
    await app.start();
    return app;
  }

  group('role', () {
    for (final (role, expected) in [
      ('BASIC', UserRole.basic),
      ('MOD', UserRole.mod),
      ('ADMIN', UserRole.admin),
    ]) {
      test('a $role device\'s role is the user\'s', () async {
        final app = await connected(role: role);

        expect(app.role, expected);
        expect(app.userId, 'user-0');
        expect(app.userName, 'Rodrigo');
      });
    }

    test('before the registration is read a device may do nothing', () async {
      final app = AppController(
        store: store,
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: backend.redeemPairing,
      );

      expect(app.role, UserRole.basic);
      expect(app.userId, isNull);
    });

    test('the tabs follow the role: People is an admin\'s', () async {
      for (final role in ['BASIC', 'MOD']) {
        expect((await connected(role: role)).tabs, [
          HomeTab.inbox,
          HomeTab.producers,
          HomeTab.settings,
        ]);
      }
      expect((await connected(role: 'ADMIN')).tabs, [
        HomeTab.inbox,
        HomeTab.producers,
        HomeTab.people,
        HomeTab.settings,
      ]);
    });

    test(
      'selecting a tab notifies once, and a disconnect returns to Inbox',
      () async {
        final app = await connected();
        var notified = 0;
        app.addListener(() => notified++);

        app.selectTab(HomeTab.settings);
        app.selectTab(HomeTab.settings);

        expect(app.tab, HomeTab.settings);
        expect(notified, 1);
        await app.disconnect();
        expect(app.tab, HomeTab.inbox);
      },
    );

    test('a role changed under the person is noticed once', () async {
      final app = await connected(role: 'ADMIN');
      expect(app.hasRoleChange, isFalse);

      backend
        ..userRole = 'MOD'
        ..admin = false;
      await app.rereadRegistration();

      expect(app.role, UserRole.mod);
      expect(app.hasRoleChange, isTrue);
      final change = app.takeRoleChange();
      expect(change?.from, UserRole.admin);
      expect(change?.to, UserRole.mod);
      expect(app.takeRoleChange(), isNull);
      await app.rereadRegistration();
      expect(app.hasRoleChange, isFalse);
    });

    test('an unchanged role says nothing', () async {
      final app = await connected(role: 'MOD');

      await app.rereadRegistration();

      expect(app.hasRoleChange, isFalse);
    });
  });

  group('the gateway', () {
    test('runs a call with the key and gives its answer', () async {
      final app = await connected();

      final who = await app.call((api) => api.getClient());

      expect(who.name, 'Pixel 8');
    });

    test('a key the server no longer accepts returns to setup', () async {
      final app = await connected();
      backend.acceptedKey = null;

      await expectLater(
        app.call((api) => api.listPeople()),
        throwsA(isA<SignedOutException>()),
      );

      expect(app.phase, ConnectionPhase.disconnected);
      expect(store.saved, isNull);
    });

    test(
      'a refused role re-reads it, and the failure is still thrown',
      () async {
        final app = await connected(role: 'ADMIN');
        // The host made them a mod meanwhile.
        backend
          ..userRole = 'MOD'
          ..admin = false;

        await expectLater(
          app.call(
            (api) => throw const ApiException('refused', statusCode: 403),
          ),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'status', 403),
          ),
        );

        expect(app.role, UserRole.mod);
        expect(app.hasRoleChange, isTrue);
      },
    );

    test('any other failure is the call\'s own', () async {
      final app = await connected();

      await expectLater(
        app.call((api) => throw const ApiException('boom', statusCode: 500)),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 500)),
      );

      expect(app.phase, ConnectionPhase.connected);
      expect(app.hasRoleChange, isFalse);
    });

    test('without a connection a call is a quiet sign-out', () async {
      final app = AppController(
        store: store,
        apiFactory: (credentials) =>
            backend.api(credentials.baseUrl, credentials.clientKey),
        redeemPairing: backend.redeemPairing,
      );

      await expectLater(
        app.call((api) => api.getClient()),
        throwsA(isA<SignedOutException>()),
      );
    });

    test('the feature controllers start afresh for a new connection', () async {
      final app = await connected();
      final before = app.producers;

      await app.disconnect();

      expect(identical(app.producers, before), isFalse);
    });
  });

  group('Resource', () {
    test('shows skeleton rows until the first read ends', () async {
      final list = Resource<List<int>>();
      expect(list.showSkeleton, isTrue);

      await list.load(() async => [1, 2]);

      expect(list.showSkeleton, isFalse);
      expect(list.value, [1, 2]);
      expect(list.loadedAt, isNotNull);
      expect(list.error, isNull);
      expect(list.loading, isFalse);
    });

    test('a first read that fails is a failure with no list', () async {
      final list = Resource<List<int>>();

      final worked = await list.load(
        () async => throw const ApiException('down', statusCode: 500),
      );

      expect(worked, isFalse);
      expect(list.failedWithoutList, isTrue);
      expect(list.stale, isFalse);
      expect(list.offline, isFalse);
    });

    test('a refresh that fails keeps the older list, stale', () async {
      final list = Resource<List<int>>();
      await list.load(() async => [1]);

      await list.load(() async => throw const ApiException('no connection'));

      expect(list.value, [1]);
      expect(list.stale, isTrue);
      expect(list.offline, isTrue);
      expect(list.failedWithoutList, isFalse);
      await list.load(() async => [2]);
      expect(list.stale, isFalse);
      expect(list.value, [2]);
    });

    test('a quiet sign-out changes nothing', () async {
      final list = Resource<List<int>>();
      await list.load(() async => [1]);

      final worked = await list.load(
        () async => throw const SignedOutException(),
      );

      expect(worked, isFalse);
      expect(list.value, [1]);
      expect(list.error, isNull);
      expect(list.loading, isFalse);
    });

    test('clears', () async {
      final list = Resource<List<int>>();
      await list.load(() async => [1]);

      list.clear();

      expect(list.hasValue, isFalse);
      expect(list.showSkeleton, isTrue);
    });
  });
}
