import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/connection/server_credentials.dart';
import 'package:signalhub_client/src/features/own_producers_controller.dart';
import 'package:signalhub_client/src/models/users.dart';

import '../support/fakes.dart';
import '../support/own_producers_fake.dart';

void main() {
  late FakeBackend backend;
  late OwnProducersFake producers;
  late InMemoryCredentialsStore store;
  late AppController app;

  setUp(() async {
    backend = FakeBackend()..userRole = 'MOD';
    producers = OwnProducersFake(backend);
    store = InMemoryCredentialsStore()
      ..saved = ServerCredentials.parse(serverUrl, clientKey);
    app = AppController(
      store: store,
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      redeemPairing: backend.redeemPairing,
      push: FakePushService(),
    );
    await app.start();
  });

  tearDown(() => app.dispose());

  OwnProducersController own() => app.ownProducers;

  group('reading', () {
    test('load keeps the producers this user owns', () async {
      producers.own('p-1', 'homelab-monitor');
      producers.own('p-2', 'garage-door');

      await own().load();

      expect(own().list.value?.map((p) => p.name), [
        'homelab-monitor',
        'garage-door',
      ]);
      expect(own().byId('p-2')?.name, 'garage-door');
      expect(own().byName('garage-door')?.id, 'p-2');
    });

    test('a failed refresh keeps the older list', () async {
      producers.own('p-1', 'homelab-monitor');
      await own().load();
      backend.offline = true;

      await own().load();

      expect(own().list.stale, isTrue);
      expect(own().list.offline, isTrue);
      expect(own().list.value, hasLength(1));
    });

    test('read one answers it and keeps it in the list', () async {
      producers.own('p-1', 'homelab-monitor');
      await own().load();
      producers.owned.single['lastEventAt'] = '2026-10-10T00:36:00Z';

      final outcome = await own().read('p-1');

      expect(outcome.value?.lastEventAt, isNotNull);
      expect(own().byId('p-1')?.lastEventAt, isNotNull);
    });

    test('a producer this user does not own is not found', () async {
      final outcome = await own().read('p-9');

      expect(outcome.failure, ProducerFailure.notFound);
      expect(outcome.message('load it'), "Couldn't load it. Try again.");
    });
  });

  group('creating', () {
    test('answers the producer with its first key, once', () async {
      final outcome = await own().create(
        'garage-door',
        ProducerVisibility.private,
      );

      expect(outcome.ok, isTrue);
      final issued = outcome.value!;
      expect(issued.producer.name, 'garage-door');
      expect(issued.producer.visibility, ProducerVisibility.private);
      expect(issued.apiKey, startsWith('shpk1_'));
      expect(producers.owned.single['name'], 'garage-door');
    });

    test('a producer made joins the list that was read', () async {
      await own().load();

      await own().create('garage-door', ProducerVisibility.public);

      expect(
        own().byName('garage-door')?.visibility,
        ProducerVisibility.public,
      );
    });

    test('a taken name is told apart from one the server refuses', () async {
      producers.hiddenNames.add('ci-pipeline');

      final taken = await own().create(
        'ci-pipeline',
        ProducerVisibility.private,
      );
      final bad = await own().create('not ok', ProducerVisibility.private);

      expect(taken.failure, ProducerFailure.taken);
      expect(bad.failure, ProducerFailure.notAllowed);
    });

    test('says what happened, never what the server titled it', () async {
      producers.failures['POST /api/v1/client/producers'] = 500;
      final server = await own().create('a', ProducerVisibility.private);
      backend.offline = true;
      final offline = await own().create('a', ProducerVisibility.private);

      expect(
        server.message('create a'),
        'SignalHub had a problem. Try again in a moment.',
      );
      expect(offline.failure, ProducerFailure.offline);
      expect(
        offline.message('create a'),
        "Couldn't create a. Check your connection and try again.",
      );
      expect(offline.message('create a'), isNot(contains('answered')));
    });
  });

  group('changing', () {
    setUp(() => producers.own('p-1', 'homelab-monitor'));

    test('rename answers the new name, and a taken one is refused', () async {
      producers.own('p-2', 'garage-door');

      final renamed = await own().rename('p-1', 'homelab-nas');
      final taken = await own().rename('p-1', 'garage-door');

      expect(renamed.value?.name, 'homelab-nas');
      expect(taken.failure, ProducerFailure.taken);
    });

    test('visibility changes and the list follows', () async {
      await own().load();

      await own().setVisibility('p-1', ProducerVisibility.public);

      expect(own().byId('p-1')?.visibility, ProducerVisibility.public);
    });

    test('a new key is in the answer only; revoking is for good', () async {
      final issued = (await own().issueKey('p-1')).value!;

      expect(issued.apiKey, isNotEmpty);
      expect(issued.producer.keys, hasLength(2));
      final revoked = (await own().revokeKey('p-1', issued.keyId)).value!;
      expect(
        revoked.keys.firstWhere((k) => k.id == issued.keyId).isRevoked,
        isTrue,
      );
      expect(revoked.workingKeys, hasLength(1));
    });

    test('disable and enable', () async {
      expect((await own().disable('p-1')).value?.isDisabled, isTrue);
      expect((await own().enable('p-1')).value?.isDisabled, isFalse);
    });

    test('enabling what the host disabled says only the host can', () async {
      producers.owned.single
        ..['disabledAt'] = '2026-10-10T09:00:00Z'
        ..['disabledByOperator'] = true;

      final outcome = await own().enable('p-1');

      expect(outcome.failure, ProducerFailure.disabledByHost);
      expect(
        outcome.message('enable homelab-monitor'),
        'Disabled by the host. Ask the host to enable it.',
      );
    });

    test('subscribing follows the visible producers', () async {
      await own().load();

      final off = await own().setSubscribed('p-1', subscribed: false);

      expect(off.value?.subscribed, isFalse);
      expect(own().byId('p-1')?.subscribed, isFalse);
      final on = await own().setSubscribed('p-1', subscribed: true);
      expect(on.value?.subscribed, isTrue);
      expect(own().byId('p-1')?.subscribed, isTrue);
    });

    test('a producer that is gone answers not found', () async {
      producers.owned.clear();

      expect((await own().disable('p-1')).failure, ProducerFailure.notFound);
      expect(
        (await own().setSubscribed('p-1', subscribed: true)).failure,
        ProducerFailure.notFound,
      );
    });
  });

  group('the allow-list', () {
    setUp(() {
      producers
        ..own('p-1', 'homelab-monitor')
        ..addPerson('u-ana', 'Ana')
        ..addPerson('u-marta', 'Marta')
        ..addPerson('u-rui', 'Rui');
    });

    test('people are names A to Z, without this user', () async {
      producers
        ..addPerson('u-bia', 'bia')
        ..addPerson('u-zed', 'Zed');

      final people = (await own().readPeople()).value!;

      expect(people.map((p) => p.name), ['Ana', 'bia', 'Marta', 'Rui', 'Zed']);
    });

    test('saves what was added and what was removed', () async {
      await own().saveAllowList('p-1', add: ['u-ana', 'u-marta'], remove: []);

      final saved = await own().saveAllowList(
        'p-1',
        add: ['u-rui'],
        remove: ['u-ana'],
      );

      expect(saved.value?.allowedUsers.map((u) => u.name), ['Marta', 'Rui']);
    });

    test('stops at the first failure, keeping what worked', () async {
      producers
              .failures['PUT /api/v1/client/producers/p-1/allowed-users/u-marta'] =
          500;

      final saved = await own().saveAllowList(
        'p-1',
        add: ['u-ana', 'u-marta', 'u-rui'],
        remove: [],
      );

      expect(saved.failure, ProducerFailure.server);
      await own().load();
      expect(own().byId('p-1')?.allowedUsers.map((u) => u.name), ['Ana']);
    });
  });

  group('what the server refuses', () {
    test('a key that is no longer accepted ends quietly', () async {
      backend.acceptedKey = null;

      final outcome = await own().create(
        'garage-door',
        ProducerVisibility.private,
      );

      expect(outcome.failure, ProducerFailure.signedOut);
      expect(outcome.message('create it'), isNull);
      expect(app.phase, ConnectionPhase.disconnected);
    });

    test('a role that no longer allows it is read again', () async {
      producers.own('p-1', 'homelab-monitor');
      expect(app.role, UserRole.mod);
      backend.userRole = 'BASIC';
      producers.failures['POST /api/v1/client/producers/p-1/disable'] = 403;

      final outcome = await own().disable('p-1');

      expect(outcome.failure, ProducerFailure.forbidden);
      expect(
        outcome.message('disable homelab-monitor'),
        "Your role doesn't allow this. It may have changed.",
      );
      expect(app.role, UserRole.basic);
    });

    test('nothing is said to a controller that was disposed', () async {
      final controller = OwnProducersController(app);
      var told = 0;
      controller.addListener(() => told++);
      producers.own('p-1', 'homelab-monitor');

      final loading = controller.load();
      controller.dispose();
      await loading;

      expect(told, 1);
    });
  });
}
