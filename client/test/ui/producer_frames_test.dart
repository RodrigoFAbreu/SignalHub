import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/models/producers.dart';
import 'package:signalhub_client/src/ui/allow_list_screen.dart';
import 'package:signalhub_client/src/ui/new_producer_screen.dart';
import 'package:signalhub_client/src/ui/producer_key_screen.dart';
import 'package:signalhub_client/src/ui/widgets/copy_button.dart';

import '../support/harness.dart';
import '../support/own_producers_fake.dart';
import '../support/phone.dart';
import '../support/producer_screens.dart';
import '../support/screenshot.dart';

/// Every frame of the drawings of a new producer, its key and its screens,
/// built from the data the frame shows. Each is a screenshot when
/// `SIGNALHUB_SCREENSHOTS` names a directory, to compare with the drawing
/// (docs/development.md, "Client"); without it they only prove that every
/// state builds.
void main() {
  setUpAll(() async {
    await loadDesignFonts();
    await loadMonospaceFont();
  });

  void frame(
    String id,
    Future<void> Function(WidgetTester tester, AppHarness app) body, {
    Size size = const Size(412, 892),
    double textScale = 1,
    Brightness brightness = Brightness.dark,
    String role = 'MOD',
  }) {
    testWidgets('frame $id', (tester) async {
      final app = AppHarness(role: role);
      useDesignPhone(
        tester,
        size: size,
        textScale: textScale,
        brightness: brightness,
      );
      FakePlatform(tester);
      await body(tester, app);
      await saveScreenshot(tester, find.byKey(screenshotKey), id);
    });
  }

  OwnProducersFake fakeOf(AppHarness app) => OwnProducersFake(app.backend)
    ..addPerson('u-ana', 'Ana')
    ..addPerson('u-joao', 'João')
    ..addPerson('u-marta', 'Marta')
    ..addPerson('u-rui', 'Rui');

  List<Map<String, Object?>> twoKeys() => [
    OwnProducersFake.key(
      'EXAMPLE1',
      prefix: 'shpk1_EXAMPLE1',
      lastUsedAt: todayAt(0, 36),
    ),
    OwnProducersFake.key(
      'EXAMPLE2',
      prefix: 'shpk1_EXAMPLE2',
      createdAt: '2026-10-02T09:00:00Z',
    ),
  ];

  const ana = {'id': 'u-ana', 'name': 'Ana'};
  const marta = {'id': 'u-marta', 'name': 'Marta'};

  Future<void> openNew(WidgetTester tester, AppHarness app) async {
    await app.start(tester);
    await pushScreen(
      tester,
      app,
      NewProducerScreen(controller: app.controller),
    );
  }

  // -- creating -----------------------------------------------------------

  frame('2a', (tester, app) async {
    fakeOf(app);
    await openNew(tester, app);
    await tester.enterText(
      find.byKey(const Key('producerName')),
      'garage-door',
    );
    await tester.pump();
    await app.settle(tester);
  });

  frame('2a1', (tester, app) async {
    fakeOf(app).hiddenNames.add('ci-pipeline');
    await openNew(tester, app);
    await tester.enterText(
      find.byKey(const Key('producerName')),
      'ci-pipeline',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('create')));
    await app.settle(tester);
  });

  frame('2a2', (tester, app) async {
    fakeOf(app);
    await openNew(tester, app);
    await tester.enterText(
      find.byKey(const Key('producerName')),
      'garage door',
    );
    await tester.pump();
    await app.settle(tester);
  });

  frame('2b3', (tester, app) async {
    final fake = fakeOf(app);
    fake.own('p-1', 'garage-door');
    await openNew(tester, app);
    await tester.enterText(
      find.byKey(const Key('producerName')),
      'garage-door',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('create')));
    await app.settle(tester);
  });

  // -- the key ------------------------------------------------------------

  Future<void> openKey(
    WidgetTester tester,
    AppHarness app, {
    bool isNew = true,
  }) async {
    fakeOf(app);
    await app.start(tester);
    await pushScreen(
      tester,
      app,
      ProducerKeyScreen(
        controller: app.controller,
        issued: sampleIssuedKey(),
        isNew: isNew,
      ),
    );
  }

  frame('2b', (tester, app) => openKey(tester, app));

  frame('2b1', (tester, app) async {
    await openKey(tester, app);
    await tester.tap(find.byType(CopyButton));
    await app.settle(tester);
  });

  frame('2b2', (tester, app) async {
    await openKey(tester, app);
    await tester.tap(find.byTooltip('Close'));
    await app.settle(tester);
  });

  frame('2b5', (tester, app) => openKey(tester, app, isNew: false));

  frame(
    '2b6',
    (tester, app) => openKey(tester, app),
    size: const Size(360, 900),
    textScale: 2,
  );

  frame(
    '5c',
    (tester, app) => openKey(tester, app),
    brightness: Brightness.light,
  );

  // -- your producer ------------------------------------------------------

  frame('2e', (tester, app) async {
    fakeOf(app).own(
      'p-1',
      'homelab-monitor',
      allowed: [ana, marta],
      keys: twoKeys(),
      lastEventAt: todayAt(0, 36),
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
  });

  frame('2e1', (tester, app) async {
    fakeOf(app).own(
      'p-1',
      'garage-door',
      keys: [OwnProducersFake.key('EXAMPLE1', prefix: 'shpk1_EXAMPLE1')],
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
  });

  frame('2g3', (tester, app) async {
    fakeOf(app).own(
      'p-1',
      'ci-pipeline',
      visibility: 'PUBLIC',
      subscribed: false,
      keys: twoKeys(),
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
  });

  frame('2b4', (tester, app) async {
    fakeOf(app).own('p-1', 'garage-door', keys: []);
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
  });

  frame('2n', (tester, app) async {
    fakeOf(app).own(
      'p-1',
      'backup-jobs',
      keys: [
        OwnProducersFake.key(
          'EXAMPLE1',
          prefix: 'shpk1_EXAMPLE1',
          revokedAt: '2026-10-04T09:00:00Z',
        ),
        OwnProducersFake.key(
          'EXAMPLE2',
          prefix: 'shpk1_EXAMPLE2',
          revokedAt: '2026-10-04T09:00:00Z',
        ),
      ],
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
  });

  frame('2o', (tester, app) async {
    fakeOf(app).own(
      'p-1',
      'garage-door',
      disabledAt: '2026-10-10T09:00:00Z',
      keys: [OwnProducersFake.key('EXAMPLE1', prefix: 'shpk1_EXAMPLE1')],
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
  });

  Future<void> hostDisabled(WidgetTester tester, AppHarness app) async {
    fakeOf(app).own(
      'p-1',
      'old-sensor',
      disabledAt: '2026-10-01T09:00:00Z',
      disabledByOperator: true,
      keys: [
        OwnProducersFake.key(
          'EXAMPLE1',
          prefix: 'shpk1_EXAMPLE1',
          createdAt: '2026-08-14T09:00:00Z',
          lastUsedAt: '2026-10-02T09:00:00Z',
        ),
      ],
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
  }

  frame('2p', hostDisabled);
  frame('5i', hostDisabled, brightness: Brightness.light);

  // -- dialogs ------------------------------------------------------------

  frame('2h', (tester, app) async {
    fakeOf(app).own('p-1', 'homelab-monitor', keys: twoKeys());
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
    await tester.tap(find.byTooltip('Rename homelab-monitor'));
    await app.settle(tester);
    await tester.enterText(
      find.byKey(const Key('producerName')),
      'homelab-nas',
    );
    await tester.pump();
    await app.settle(tester);
  });

  Future<void> revokeDialog(WidgetTester tester, AppHarness app) async {
    fakeOf(app).own('p-1', 'homelab-monitor', keys: twoKeys());
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
    await tester.tap(find.widgetWithText(TextButton, 'Revoke').first);
    await app.settle(tester);
  }

  frame('2i', revokeDialog);
  frame('5f', revokeDialog, brightness: Brightness.light);

  frame('2j', (tester, app) async {
    fakeOf(app).own(
      'p-1',
      'backup-jobs',
      keys: [
        OwnProducersFake.key(
          'EXAMPLE1',
          prefix: 'shpk1_EXAMPLE1',
          createdAt: '2026-09-20T09:00:00Z',
          lastUsedAt: '2026-10-03T09:00:00Z',
        ),
      ],
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
    await tester.tap(find.widgetWithText(TextButton, 'Revoke'));
    await app.settle(tester);
  });

  frame('2k', (tester, app) async {
    fakeOf(app).own('p-1', 'homelab-monitor', keys: twoKeys());
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
    await tester.ensureVisible(find.byKey(const Key('disable')));
    await tester.tap(find.byKey(const Key('disable')));
    await app.settle(tester);
  });

  frame('2l', (tester, app) async {
    fakeOf(app)
        .own('p-1', 'homelab-monitor', allowed: [ana, marta], keys: twoKeys());
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
    await tester.tap(find.byTooltip('Remove Marta'));
    await app.settle(tester);
  });

  frame('2m', (tester, app) async {
    fakeOf(app).own(
      'p-1',
      'ci-pipeline',
      visibility: 'PUBLIC',
      allowed: [ana],
      keys: twoKeys(),
    );
    await app.start(tester);
    await openProducer(tester, app, 'p-1');
    await tester.tap(find.text('Private'));
    await app.settle(tester);
  });

  // -- someone else's producer --------------------------------------------

  frame('2g', (tester, app) async {
    fakeOf(app).other('p-3', 'ana-reports', 'Ana', subscribed: true);
    await app.start(tester);
    await openProducer(tester, app, 'p-3');
  });

  frame('2g1', (tester, app) async {
    fakeOf(app).other('p-3', 'weather-alerts', 'João');
    await app.start(tester);
    await openProducer(tester, app, 'p-3');
  });

  frame('2g2', (tester, app) async {
    fakeOf(app).other(
      'p-3',
      'family-calendar',
      'Ana',
      visibility: 'PRIVATE',
      subscribed: true,
    );
    app.backend.pushPreferences = {
      ...app.backend.pushPreferences!,
      'mutedProducerIds': ['p-3'],
    };
    await app.start(tester);
    await openProducer(tester, app, 'p-3');
  });

  frame('2q', (tester, app) async {
    fakeOf(app);
    await app.start(tester);
    await openProducer(tester, app, 'p-gone');
  });

  // -- adding people ------------------------------------------------------

  Future<void> openAllowList(
    WidgetTester tester,
    AppHarness app,
    OwnProducersFake fake,
  ) async {
    await app.start(tester);
    await app.controller.ownProducers.load();
    final producer = OwnProducer.fromJson(fake.owned.single);
    await pushScreen(
      tester,
      app,
      AllowListScreen(controller: app.controller, producer: producer),
    );
  }

  frame('2f', (tester, app) async {
    final fake = fakeOf(app)
      ..own('p-1', 'homelab-monitor', allowed: [ana, marta], keys: twoKeys());
    await openAllowList(tester, app, fake);
  });

  frame('2f1', (tester, app) async {
    final fake = OwnProducersFake(app.backend)
      ..own('p-1', 'garage-door', keys: twoKeys());
    await openAllowList(tester, app, fake);
  });

  frame('2f2', (tester, app) async {
    final fake = fakeOf(app);
    for (final (id, name) in [
      ('u-mariana', 'Mariana'),
      ('u-mateus', 'Mateus'),
      ('u-amadeu', 'Amadeu'),
      ('u-bruno', 'Bruno'),
      ('u-carla', 'Carla'),
      ('u-diogo', 'Diogo'),
    ]) {
      fake.addPerson(id, name);
    }
    fake.own(
      'p-1',
      'homelab-monitor',
      allowed: [
        marta,
        {'id': 'u-mariana', 'name': 'Mariana'},
        {'id': 'u-amadeu', 'name': 'Amadeu'},
      ],
      keys: twoKeys(),
    );
    fake.failures['PUT /api/v1/client/producers/p-1/allowed-users/u-mateus'] =
        500;
    await openAllowList(tester, app, fake);
    await tester.enterText(find.byType(TextField), 'ma');
    await tester.pump();
    await app.settle(tester);
    await tester.tap(find.text('Mateus'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveAllowList')));
    await app.settle(tester);
  });

  frame('2f3', (tester, app) async {
    final fake = fakeOf(app)
      ..own('p-1', 'homelab-monitor', allowed: [ana, marta], keys: twoKeys());
    await openAllowList(tester, app, fake);
    await tester.tap(find.text('Marta'));
    await tester.tap(find.text('Rui'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('saveAllowList')));
    await app.settle(tester);
  });
}
