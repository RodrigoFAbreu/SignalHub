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
  const critical = CriticalAlertSettings(
    different: true,
    alert: AlertSettings(
      sound: AlertSound.glass,
      volume: 90,
      vibration: AlertVibration.strong,
    ),
    onSilent: false,
    duringDoNotDisturb: false,
  );

  test('a new installation saves the defaults for the first push', () async {
    await alert.load();

    expect(alert.settings, AlertSettings.defaults);
    expect(alert.critical, CriticalAlertSettings.defaults);
    expect(platform.saved, [
      platformAlerts(AlertSettings.defaults, CriticalAlertSettings.defaults),
    ]);
    expect(platform.previewed, isEmpty);
  });

  test('restores the saved settings without saving again', () async {
    platform.stored = jsonEncode(platformAlerts(chosen, critical));

    await alert.load();

    expect(alert.settings, chosen);
    expect(alert.critical, critical);
    expect(platform.saved, isEmpty);
  });

  test('keeps a general alert saved before critical alerts, and saves '
      'their defaults next to it', () async {
    platform.stored = jsonEncode(chosen.toPlatform());

    await alert.load();

    expect(alert.settings, chosen);
    expect(alert.critical, CriticalAlertSettings.defaults);
    expect(platform.saved, [
      platformAlerts(chosen, CriticalAlertSettings.defaults),
    ]);
  });

  test('keeps settings saved before patterns and lengths, and saves them '
      'again with the new settings at their defaults', () async {
    // As a version without patterns and lengths saved them.
    Map<String, Object?> older(Map<String, Object?> alert) => {...alert}
      ..remove('pattern')
      ..remove('length');
    final saved = platformAlerts(chosen, critical);
    platform.stored = jsonEncode({
      ...older(saved),
      'critical': older(saved['critical']! as Map<String, Object?>),
      'criticalAlert': older(saved['criticalAlert']! as Map<String, Object?>),
    });

    await alert.load();

    expect(alert.settings, chosen);
    expect(alert.settings.pattern, AlertPattern.standard);
    final withDefaults = critical.copyWith(
      alert: critical.alert.copyWith(
        pattern: AlertPattern.rapid,
        length: AlertLength.long,
      ),
    );
    expect(alert.critical, withDefaults);
    // A critical push now plays the new default pattern and length.
    expect(platform.saved, [platformAlerts(chosen, withDefaults)]);
  });

  test('a change is saved at once and survives a restart', () async {
    await alert.load();

    await alert.change(chosen);
    final restarted = AlertController(platform);
    await restarted.load();

    expect(
      platform.saved.last,
      platformAlerts(chosen, CriticalAlertSettings.defaults),
    );
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

  test('a new pattern or length is previewed without sound', () async {
    await alert.load();

    await alert.change(
      AlertSettings.defaults.copyWith(pattern: AlertPattern.heartbeat),
    );
    await alert.change(alert.settings.copyWith(length: AlertLength.long));

    expect(platform.previewed, [
      AlertSettings.defaults
          .copyWith(sound: () => null, pattern: AlertPattern.heartbeat)
          .toPlatform(),
      AlertSettings.defaults
          .copyWith(
            sound: () => null,
            pattern: AlertPattern.heartbeat,
            length: AlertLength.long,
          )
          .toPlatform(),
    ]);
    expect(platform.saved.last['pattern'], 'heartbeat');
    expect(platform.saved.last['length'], 'long');
  });

  test('a pattern or length chosen while the vibration is off plays '
      'nothing', () async {
    await alert.load();
    await alert.change(
      AlertSettings.defaults.copyWith(vibration: AlertVibration.off),
    );
    platform.previewed.clear();

    await alert.change(alert.settings.copyWith(pattern: AlertPattern.steady));

    expect(platform.previewed, isEmpty);
    expect(alert.settings.pattern, AlertPattern.steady);
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

  group('critical pushes', () {
    Map<String, Object?> criticalAlert() =>
        platform.saved.last['criticalAlert']! as Map<String, Object?>;

    test('play the general alert until the switch is on', () async {
      await alert.load();

      expect(criticalAlert()['resource'], 'signalhub_signal');

      await alert.changeCritical(critical.copyWith(different: false));
      expect(criticalAlert()['resource'], 'signalhub_signal');
      expect(platform.previewed, isEmpty);

      await alert.changeCritical(critical);
      expect(criticalAlert()['resource'], 'signalhub_glass');
      // Every other push keeps the general alert.
      expect(platform.saved.last['resource'], 'signalhub_signal');
    });

    test('a general alert changed later is still theirs while the switch '
        'is off', () async {
      await alert.load();

      await alert.change(chosen);

      expect(criticalAlert()['resource'], 'signalhub_pulse');
      expect(criticalAlert()['onSilent'], isTrue);
    });

    test(
      'their own sound or vibration is previewed as a critical push',
      () async {
        await alert.load();
        await alert.changeCritical(alert.critical.copyWith(different: true));

        await alert.changeCritical(
          alert.critical.copyWith(
            alert: alert.critical.alert.copyWith(
              sound: () => AlertSound.beacon,
            ),
          ),
        );
        await alert.changeCritical(
          alert.critical.copyWith(
            alert: alert.critical.alert.copyWith(
              vibration: AlertVibration.light,
            ),
          ),
        );

        await alert.changeCritical(
          alert.critical.copyWith(
            alert: alert.critical.alert.copyWith(
              pattern: AlertPattern.heartbeat,
            ),
          ),
        );

        expect(platform.previewed, hasLength(3));
        expect(platform.previewed.last, {
          ...CriticalAlertSettings.defaults.alert
              .copyWith(
                sound: () => null,
                vibration: AlertVibration.light,
                pattern: AlertPattern.heartbeat,
              )
              .toPlatform(),
          'onSilent': true,
          'duringDoNotDisturb': false,
        });
        platform.previewed.removeLast();
        expect(platform.previewed.first, {
          ...CriticalAlertSettings.defaults.alert
              .copyWith(
                sound: () => AlertSound.beacon,
                vibration: AlertVibration.off,
              )
              .toPlatform(),
          'onSilent': true,
          'duringDoNotDisturb': false,
        });
        expect(platform.previewed.last['resource'], isNull);
        expect(platform.previewed.last['amplitudes'], contains(70));
      },
    );

    group('on silent', () {
      setUp(() => platform.silent = true);

      test('sound by default, unlike every other push', () async {
        await alert.load();

        expect(await alert.previewCritical(chosen), isNull);
        expect(
          await alert.preview(chosen),
          contains('Silent mode or Do Not Disturb'),
        );
      });

      test('stay quiet with the switch off', () async {
        await alert.load();
        await alert.changeCritical(alert.critical.copyWith(onSilent: false));

        expect(criticalAlert()['onSilent'], isFalse);
        expect(
          await alert.previewCritical(chosen),
          contains('Silent mode or Do Not Disturb'),
        );
      });
    });

    group('during Do Not Disturb', () {
      setUp(() => platform.doNotDisturb = true);

      test('stay quiet by default, as every other push', () async {
        platform.access = true;
        await alert.load();

        expect(
          await alert.previewCritical(chosen),
          contains('Silent mode or Do Not Disturb'),
        );
        expect(
          await alert.preview(chosen),
          contains('Silent mode or Do Not Disturb'),
        );
      });

      test('sound with the switch on and the access given', () async {
        platform.access = true;
        await alert.load();

        final message = await alert.changeCritical(
          alert.critical.copyWith(duringDoNotDisturb: true),
        );

        expect(message, isNull);
        expect(alert.criticalDuringDoNotDisturb, isTrue);
        expect(criticalAlert()['duringDoNotDisturb'], isTrue);
        expect(await alert.previewCritical(chosen), isNull);
        expect(platform.accessOpened, 0);
      });

      test('without the access, the switch stays off and the system screen '
          'to give it opens', () async {
        await alert.load();
        final saved = platform.saved.length;

        final message = await alert.changeCritical(
          alert.critical.copyWith(duringDoNotDisturb: true),
        );

        expect(message, contains('Do Not Disturb access'));
        expect(platform.accessOpened, 1);
        expect(alert.critical.duringDoNotDisturb, isFalse);
        expect(alert.criticalDuringDoNotDisturb, isFalse);
        expect(platform.saved, hasLength(saved));
      });

      test('the access given in the meantime is read again', () async {
        await alert.load();
        await alert.changeCritical(
          alert.critical.copyWith(duringDoNotDisturb: true),
        );
        platform.access = true;

        await alert.refreshDoNotDisturbAccess();
        await alert.changeCritical(
          alert.critical.copyWith(duringDoNotDisturb: true),
        );

        expect(alert.criticalDuringDoNotDisturb, isTrue);
        expect(platform.accessOpened, 1);
      });

      test('the access taken away turns the switch off', () async {
        platform.access = true;
        platform.stored = jsonEncode(
          platformAlerts(chosen, critical.copyWith(duringDoNotDisturb: true)),
        );
        await alert.load();
        expect(alert.criticalDuringDoNotDisturb, isTrue);

        platform.access = false;
        await alert.refreshDoNotDisturbAccess();

        expect(alert.criticalDuringDoNotDisturb, isFalse);
        // Without the access, the phone keeps it quiet.
        expect(
          await alert.previewCritical(chosen),
          contains('Silent mode or Do Not Disturb'),
        );
      });
    });

    test('a critical setting not saved is not kept', () async {
      await alert.load();
      platform.failsToSave = true;

      final message = await alert.changeCritical(critical);

      expect(message, 'The alert setting could not be saved');
      expect(alert.critical, CriticalAlertSettings.defaults);
      expect(platform.previewed, isEmpty);
    });
  });
}
