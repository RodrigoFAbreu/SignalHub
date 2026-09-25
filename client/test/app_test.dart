import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app.dart';
import 'package:signalhub_client/src/app_controller.dart';
import 'package:signalhub_client/src/push/push_service.dart';

import 'support/fakes.dart';

void main() {
  late FakeBackend backend;
  late FakePushService push;
  late AppController controller;

  setUp(() {
    backend = FakeBackend()..publish('e-1', 'Nightly build failed');
    push = FakePushService();
    controller = AppController(
      store: InMemoryCredentialsStore(),
      apiFactory: (credentials) =>
          backend.api(credentials.baseUrl, credentials.clientKey),
      push: push,
    );
  });

  Future<void> connect(WidgetTester tester, {String key = clientKey}) async {
    await tester.pumpWidget(SignalHubApp(controller: controller));
    await tester.runAsync(controller.start);
    await tester.pump();
    await tester.enterText(find.byKey(const Key('serverUrl')), serverUrl);
    await tester.enterText(find.byKey(const Key('clientKey')), key);
    await tester.tap(find.byKey(const Key('connect')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  testWidgets('sets up a device and shows its status', (tester) async {
    await connect(tester);

    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text(serverUrl), findsOneWidget);
    expect(find.text('Push notifications are on'), findsOneWidget);
    expect(find.text('Nightly build failed'), findsOneWidget);
    expect(
      find.textContaining('Blocked · High · nightly-build'),
      findsOneWidget,
    );
  });

  testWidgets('shows why setup failed', (tester) async {
    backend.acceptedKey = null;

    await connect(tester);

    expect(
      find.text('The server did not accept this client key'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('connect')), findsOneWidget);
  });

  testWidgets('shows pushes received while open', (tester) async {
    await connect(tester);

    push.received.add(
      const PushNotice(title: 'Deploy done', body: 'v1.2.3', eventId: 'e-2'),
    );
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    expect(find.text('Received while open'), findsOneWidget);
    expect(find.text('Deploy done'), findsOneWidget);
    expect(find.text('v1.2.3'), findsOneWidget);
  });

  testWidgets('disconnecting returns to setup', (tester) async {
    await connect(tester);

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('disconnect')));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('connect')), findsOneWidget);
    expect(backend.pushTarget, isNull);
  });
}
