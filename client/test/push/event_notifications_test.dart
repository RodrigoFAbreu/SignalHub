import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/push/event_notifications.dart';

/// The app's way to take an answered question's notification off the phone
/// (`MainActivity.kt`), against a fake platform.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'io.github.rodrigofabreu.signalhub/notifications',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'asks the platform to remove the notification by the event ID',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });

      await removeEventNotification('e-1');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'remove');
      expect(calls.single.arguments, 'e-1');
    },
  );

  test('a platform that refuses, or has no channel, changes nothing', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'unavailable'),
    );
    await expectLater(removeEventNotification('e-1'), completes);

    messenger.setMockMethodCallHandler(channel, null);
    await expectLater(removeEventNotification('e-1'), completes);
  });
}
