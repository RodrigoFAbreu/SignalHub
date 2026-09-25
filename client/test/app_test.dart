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

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
  }

  testWidgets('sets up a device and shows its inbox', (tester) async {
    await connect(tester);

    expect(find.text('Nightly build failed'), findsOneWidget);
    expect(
      find.textContaining('Blocked · High · nightly-build · '),
      findsOneWidget,
    );
  });

  testWidgets('shows this device and its push status', (tester) async {
    await connect(tester);

    await tester.tap(find.byType(PopupMenuButton<void>));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('device')));
    await tester.pumpAndSettle();

    expect(find.text('Pixel 8'), findsOneWidget);
    expect(find.text(serverUrl), findsOneWidget);
    expect(find.text('Push notifications are on'), findsOneWidget);
  });

  testWidgets('an empty inbox says so', (tester) async {
    backend.events.clear();

    await connect(tester);

    expect(find.text('No events yet'), findsOneWidget);
  });

  testWidgets('tapping an event shows all of it', (tester) async {
    backend.publish(
      'e-2',
      'Deploy done',
      message: 'v1.2.3 is live.',
      context: 'homelab',
    );
    await connect(tester);

    await tester.tap(find.text('Deploy done'));
    await tester.pumpAndSettle();

    expect(find.text('v1.2.3 is live.'), findsOneWidget);
    expect(find.text('Blocked'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('nightly-build'), findsOneWidget);
    expect(find.text('homelab'), findsOneWidget);
    expect(find.text('e-2'), findsOneWidget);
    // Metadata is shown as the producer sent it.
    expect(find.text('{\n  "run": 7\n}'), findsOneWidget);
  });

  testWidgets('scrolling down loads older events', (tester) async {
    for (var i = 2; i <= AppController.pageSize + 5; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    await connect(tester);
    expect(find.text('Nightly build failed'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Nightly build failed'),
      500,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Nightly build failed'), findsOneWidget);
    expect(controller.hasMore, isFalse);
  });

  testWidgets('a failed older page can be retried', (tester) async {
    for (var i = 2; i <= AppController.pageSize + 1; i++) {
      backend.publish('e-$i', 'Event $i');
    }
    await connect(tester);
    backend.offline = true;

    await tester.scrollUntilVisible(
      find.byKey(const Key('loadMoreRetry')),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    backend.offline = false;
    await tester.tap(find.byKey(const Key('loadMoreRetry')));
    await settle(tester);

    expect(find.text('Nightly build failed'), findsOneWidget);
  });

  Finder unreadDot(String title) => find.descendant(
    of: find.widgetWithText(ListTile, title),
    matching: find.byKey(const Key('unread')),
  );

  testWidgets('shows which events are unread and how many', (tester) async {
    backend
      ..publish('e-2', 'Seen', readAt: '2026-09-25T12:04:00Z')
      ..publish('e-3', 'Deploy done');

    await connect(tester);

    expect(unreadDot('Nightly build failed'), findsOneWidget);
    expect(unreadDot('Deploy done'), findsOneWidget);
    expect(unreadDot('Seen'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('unreadCount')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('opening an event marks it read', (tester) async {
    await connect(tester);

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);
    expect(backend.isRead('e-1'), isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(unreadDot('Nightly build failed'), findsNothing);
    expect(find.byKey(const Key('unreadCount')), findsNothing);
  });

  testWidgets('an event can be marked unread again', (tester) async {
    backend.events.single['readAt'] = '2026-09-25T12:04:00Z';
    await connect(tester);

    await tester.tap(find.text('Nightly build failed'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('markUnread')));
    await settle(tester);

    // Back in the inbox, unread.
    expect(find.byKey(const Key('markUnread')), findsNothing);
    expect(backend.isRead('e-1'), isFalse);
    expect(unreadDot('Nightly build failed'), findsOneWidget);
  });

  testWidgets('marks everything shown read', (tester) async {
    backend.publish('e-2', 'Deploy done');
    await connect(tester);

    await tester.tap(find.byKey(const Key('markAllRead')));
    await settle(tester);

    expect(backend.isRead('e-1') && backend.isRead('e-2'), isTrue);
    expect(find.byKey(const Key('unread')), findsNothing);
    expect(find.byKey(const Key('unreadCount')), findsNothing);
    final button = tester.widget<IconButton>(
      find.byKey(const Key('markAllRead')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('a failed mark all read says why', (tester) async {
    await connect(tester);
    backend.offline = true;

    await tester.tap(find.byKey(const Key('markAllRead')));
    await settle(tester);

    expect(find.text('Could not reach the server'), findsOneWidget);
    expect(unreadDot('Nightly build failed'), findsOneWidget);
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

  testWidgets('a push received while open shows up in the inbox', (
    tester,
  ) async {
    await connect(tester);
    backend.publish('e-2', 'Deploy done');

    push.received.add(
      const PushNotice(title: 'Deploy done', body: 'v1.2.3', eventId: 'e-2'),
    );
    await settle(tester);

    expect(find.text('Deploy done'), findsOneWidget);
  });

  testWidgets('a tapped notification opens its event', (tester) async {
    await connect(tester);
    backend.publish('e-2', 'Deploy done', message: 'v1.2.3 is live.');

    push.received.add(
      const PushNotice(title: 'Deploy done', eventId: 'e-2', opened: true),
    );
    await settle(tester);

    expect(find.text('v1.2.3 is live.'), findsOneWidget);
    expect(find.text('e-2'), findsOneWidget);
    expect(backend.isRead('e-2'), isTrue);
  });

  testWidgets('a notification for an unknown event says so', (tester) async {
    await connect(tester);

    push.received.add(
      const PushNotice(title: 'Gone', eventId: 'e-404', opened: true),
    );
    await settle(tester);

    expect(
      find.text('This event does not exist on the server'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('retryEvent')), findsOneWidget);
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
