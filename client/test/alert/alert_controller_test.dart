import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/alert/alert_controller.dart';
import 'package:signalhub_client/src/alert/alert_settings.dart';

import '../support/fakes.dart';

void main() {
  late FakeAlertPlatform platform;
  late AlertController alert;

  setUp(() {
    platform = FakeAlertPlatform();
    alert = AlertController(platform);
  });

  const chosen = AlertSettings(
    sound: AlertSound.pulse,
    volume: 40,
    vibration: AlertVibration.light,
  );

  test('a new installation saves the defaults for the first push', () async {
    await alert.load();

    expect(alert.settings, AlertSettings.defaults);
    expect(platform.saved, [AlertSettings.defaults.toPlatform()]);
    expect(platform.previewed, isEmpty);
  });

  test('restores the saved settings without saving again', () async {
    platform.stored = jsonEncode(chosen.toPlatform());

    await alert.load();

    expect(alert.settings, chosen);
    expect(platform.saved, isEmpty);
  });

  test('a change is saved at once and survives a restart', () async {
    await alert.load();

    await alert.change(chosen);
    final restarted = AlertController(platform);
    await restarted.load();

    expect(platform.saved.last, chosen.toPlatform());
    expect(restarted.settings, chosen);
  });

  test('a new sound or volume is previewed without vibrating', () async {
    await alert.load();

    await alert.change(
      AlertSettings.defaults.copyWith(sound: () => AlertSound.beacon),
    );
    await alert.change(alert.settings.copyWith(volume: 30));

    expect(platform.previewed, [
      AlertSettings.defaults
          .copyWith(
            sound: () => AlertSound.beacon,
            vibration: AlertVibration.off,
          )
          .toPlatform(),
      AlertSettings.defaults
          .copyWith(
            sound: () => AlertSound.beacon,
            volume: 30,
            vibration: AlertVibration.off,
          )
          .toPlatform(),
    ]);
  });

  test('a new vibration is previewed without sound', () async {
    await alert.load();

    await alert.change(
      AlertSettings.defaults.copyWith(vibration: AlertVibration.strong),
    );

    expect(platform.previewed.single, {
      ...AlertSettings.defaults
          .copyWith(sound: () => null, vibration: AlertVibration.strong)
          .toPlatform(),
    });
  });

  test('choosing no sound plays nothing', () async {
    await alert.load();

    final message = await alert.change(
      AlertSettings.defaults.copyWith(sound: () => null),
    );

    expect(message, isNull);
    expect(platform.previewed, isEmpty);
    expect(platform.saved.last['resource'], isNull);
  });

  test('says when the phone keeps the preview quiet', () async {
    await alert.load();
    platform.plays = false;

    final message = await alert.change(chosen);

    expect(message, contains('Silent mode or Do Not Disturb'));
    expect(alert.settings, chosen);
  });

  test('a setting not saved is not kept', () async {
    await alert.load();
    platform.failsToSave = true;

    final message = await alert.change(chosen);

    expect(message, 'The alert setting could not be saved');
    expect(alert.settings, AlertSettings.defaults);
    expect(platform.previewed, isEmpty);
  });

  test('an unchanged setting is neither saved nor previewed', () async {
    await alert.load();

    await alert.change(AlertSettings.defaults);

    expect(platform.saved, hasLength(1));
    expect(platform.previewed, isEmpty);
  });
}
