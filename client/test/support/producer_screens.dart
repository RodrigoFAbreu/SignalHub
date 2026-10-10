import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/models/producers.dart';
import 'package:signalhub_client/src/ui/producer_screen.dart';

import 'harness.dart';
import 'own_producers_fake.dart';

/// Pushes [screen] over the connected app, as a tab would, and lets what it
/// reads finish.
Future<void> pushScreen(
  WidgetTester tester,
  AppHarness app,
  Widget screen,
) async {
  final context = tester.element(find.byType(Scaffold).first);
  unawaited(
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)),
  );
  await app.settle(tester);
}

Future<void> openProducer(WidgetTester tester, AppHarness app, String id) =>
    pushScreen(
      tester,
      app,
      ProducerScreen(controller: app.controller, producerId: id),
    );

/// A time of today in the phone's own zone, as the API sends it.
String todayAt(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  ).toUtc().toIso8601String();
}

/// What the platform gets: the clipboard and the share sheet. Restored when
/// the test ends.
class FakePlatform {
  FakePlatform(WidgetTester tester) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        if (refuseClipboard) throw PlatformException(code: 'unavailable');
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_shareChannel, (call) async {
      if (!shareAvailable) throw MissingPluginException();
      shared.add(call.arguments as String);
      return true;
    });
    addTearDown(() {
      messenger
        ..setMockMethodCallHandler(SystemChannels.platform, null)
        ..setMockMethodCallHandler(_shareChannel, null);
    });
  }

  static const _shareChannel = MethodChannel(
    'io.github.rodrigofabreu.signalhub/share',
  );

  final copied = <String>[];
  final shared = <String>[];
  bool refuseClipboard = false;
  bool shareAvailable = true;
}

/// The producer of the drawings' key screen, with its key: the sample key,
/// plainly not real.
IssuedProducerKey sampleIssuedKey({String name = 'garage-door'}) =>
    IssuedProducerKey(
      producer: OwnProducer.fromJson({
        'id': 'p-9',
        'name': name,
        'createdAt': '2026-10-10T09:00:00Z',
        'visibility': 'PRIVATE',
        'subscribed': true,
        'allowedUsers': <Object?>[],
        'keys': [OwnProducersFake.key('EXAMPLE1')],
      }),
      keyId: 'EXAMPLE1',
      apiKey: sampleKey,
    );

const sampleKey = 'shpk1_EXAMPLEKEY-not-a-real-key-0000';

/// Where a screen's snackbar says what happened.
Finder snack(String text) =>
    find.descendant(of: find.byType(SnackBar), matching: find.text(text));

/// Loads Roboto Mono from the Flutter SDK as the `monospace` family the key
/// and its send example are set in, so a screenshot shows real text and wraps
/// as the phone does. Does nothing where the SDK has no such font.
Future<void> loadMonospaceFont() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/dart-sdk/bin/resources/devtools/assets/fonts/'
    'Roboto_Mono/RobotoMono-Regular.ttf',
  );
  if (!file.existsSync()) return;
  final loader = FontLoader('monospace')
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
}
