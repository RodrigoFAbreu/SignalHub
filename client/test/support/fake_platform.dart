import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The platform's share sheet and clipboard, and what a screen reader is
/// told, recorded for the tests of the pairing code screen. Created inside a
/// test; it lets go of the platform channels when the test ends.
class FakePlatform {
  FakePlatform(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_shareChannel, (call) async {
      shared.add((call.arguments as Map)['text'] as String);
      if (shareFails) throw PlatformException(code: 'error');
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    messenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility,
      (message) async {
        final map = message as Map;
        if (map['type'] == 'announce') {
          announced.add((map['data'] as Map)['message'] as String);
        }
        return null;
      },
    );
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(_shareChannel, null)
        ..setMockMethodCallHandler(SystemChannels.platform, null)
        ..setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        );
    });
  }

  static const _shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

  /// The texts handed to the share sheet.
  final shared = <String>[];

  /// The texts put on the clipboard.
  final copied = <String>[];

  /// What a screen reader was told with an announcement.
  final announced = <String>[];

  /// Whether the share sheet fails to open.
  bool shareFails = false;
}
