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
  );
  const quiet = QuietModeSettings(
    onSilent: SoundThrough.all,
    duringDoNotDisturb: SoundThrough.off,
  );

  /// What a preview of the general alert plays, with the default quiet
  /// modes: never on silent or during Do Not Disturb.
  Map<String, Object?> asNormalPush(AlertSettings alert) => {
    ...alert.toPlatform(),
    'onSilent': false,
    'duringDoNotDisturb': false,
  };

  test('a new installation saves the defaults for the first push', () async {
    await alert.load();

    expect(alert.settings, AlertSettings.defaults);
    expect(alert.critical, CriticalAlertSettings.defaults);
    expect(platform.saved, [
      platformAlerts(
        AlertSettings.defaults,
        CriticalAlertSettings.defaults,
        QuietModeSettings.defaults,
      ),
    ]);
    expect(platform.previewed, isEmpty);
  });

  test('restores the saved settings without saving again', () async {
    platform.stored = jsonEncode(platformAlerts(chosen, critical, quiet));

    await alert.load();

    expect(alert.settings, chosen);
    expect(alert.critical, critical);
    expect(alert.quiet, quiet);
    expect(platform.saved, isEmpty);
  });

  test('keeps a general alert saved before critical alerts, and saves '
      'their defaults next to it', () async {
    platform.stored = jsonEncode(chosen.toPlatform());

    await alert.load();

    expect(alert.settings, chosen);
    expect(alert.critical, CriticalAlertSettings.defaults);
    expect(alert.quiet, QuietModeSettings.defaults);
    expect(platform.saved, [
      platformAlerts(
        chosen,
        CriticalAlertSettings.defaults,
        QuietModeSettings.defaults,
      ),
    ]);
  });

  test('carries over the critical switches for silent mode and Do Not '
      'Disturb, and saves them as the choices', () async {
    // As a version with the critical-only switches saved them.
    final saved = platformAlerts(chosen, critical, quiet);
    platform.stored = jsonEncode(
      {
        ...saved,
        'onSilent': null,
        'duringDoNotDisturb': null,
        'quiet': null,
        'critical': {
          ...saved['critical']! as Map<String, Object?>,
          'onSilent': false,
          'duringDoNotDisturb': true,
        },
      }..removeWhere((_, value) => value == null),
    );

    await alert.load();

    const carried = QuietModeSettings(
      onSilent: SoundThrough.off,
      duringDoNotDisturb: SoundThrough.critical,
    );
    expect(alert.settings, chosen);
    expect(alert.critical, critical);
    expect(alert.quiet, carried);
    expect(platform.saved, [platformAlerts(chosen, critical, carried)]);
  });

  test('keeps settings saved before patterns and lengths, and saves them '
      'again with the new settings at their defaults', () async {
    // As a version without patterns and lengths saved them.
    Map<String, Object?> older(Map<String, Object?> alert) => {...alert}
      ..remove('pattern')
      ..remove('length');
    final saved = platformAlerts(chosen, critical, quiet);
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
    expect(platform.saved, [platformAlerts(chosen, withDefaults, quiet)]);
  });

  test('a change is saved at once and survives a restart', () async {
    await alert.load();

    await alert.change(chosen);
    final restarted = AlertController(platform);
    await restarted.load();

    expect(
      platform.saved.last,
      platformAlerts(
        chosen,
        CriticalAlertSettings.defaults,
        QuietModeSettings.defaults,
      ),
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
      asNormalPush(
        AlertSettings.defaults.copyWith(
          sound: () => AlertSound.beacon,
          vibration: AlertVibration.off,
        ),
      ),
      asNormalPush(
        AlertSettings.defaults.copyWith(
          sound: () => AlertSound.beacon,
          volume: 30,
          vibration: AlertVibration.off,
        ),
      ),
    ]);
  });

  test('a new vibration is previewed without sound', () async {
    await alert.load();

    await alert.change(
      AlertSettings.defaults.copyWith(vibration: AlertVibration.strong),
    );

    expect(
      platform.previewed.single,
      asNormalPush(
        AlertSettings.defaults.copyWith(
          sound: () => null,
          vibration: AlertVibration.strong,
        ),
      ),
    );
  });

  test('a new pattern or length is previewed without sound', () async {
    await alert.load();

    await alert.change(
      AlertSettings.defaults.copyWith(pattern: AlertPattern.heartbeat),
    );
    await alert.change(alert.settings.copyWith(length: AlertLength.long));

    expect(platform.previewed, [
      asNormalPush(
        AlertSettings.defaults.copyWith(
          sound: () => null,
          pattern: AlertPattern.heartbeat,
        ),
      ),
      asNormalPush(
        AlertSettings.defaults.copyWith(
          sound: () => null,
          pattern: AlertPattern.heartbeat,
          length: AlertLength.long,
        ),
      ),
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

    test('a general alert changed later sounds on silent as a critical '
        'push', () async {
      await alert.load();
      await alert.change(chosen);

      expect(criticalAlert()['onSilent'], isTrue);
      expect(platform.saved.last['onSilent'], isFalse);
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

  group('on silent', () {
    setUp(() => platform.silent = true);
    Map<String, Object?> criticalAlert() =>
        platform.saved.last['criticalAlert']! as Map<String, Object?>;

    test('by default only critical pushes sound', () async {
      await alert.load();

      expect(await alert.previewCritical(chosen), isNull);
      expect(
        await alert.preview(chosen),
        contains('Silent mode or Do Not Disturb'),
      );
    });

    test('none sound with Off', () async {
      await alert.load();

      expect(await alert.changeOnSilent(SoundThrough.off), isNull);

      expect(alert.quiet.onSilent, SoundThrough.off);
      expect(platform.saved.last['onSilent'], isFalse);
      expect(criticalAlert()['onSilent'], isFalse);
      expect(
        await alert.previewCritical(chosen),
        contains('Silent mode or Do Not Disturb'),
      );
    });

    test('every push sounds with All pushes', () async {
      await alert.load();

      await alert.changeOnSilent(SoundThrough.all);

      expect(platform.saved.last['onSilent'], isTrue);
      expect(criticalAlert()['onSilent'], isTrue);
      expect(await alert.preview(chosen), isNull);
      expect(await alert.previewCritical(chosen), isNull);
      // The choice is its own: the critical settings are unchanged.
      expect(alert.critical, CriticalAlertSettings.defaults);
    });

    test('a choice not saved is not kept', () async {
      await alert.load();
      platform.failsToSave = true;

      final message = await alert.changeOnSilent(SoundThrough.all);

      expect(message, 'The alert setting could not be saved');
      expect(alert.quiet, QuietModeSettings.defaults);
    });
  });

  group('during Do Not Disturb', () {
    setUp(() => platform.doNotDisturb = true);
    Map<String, Object?> criticalAlert() =>
        platform.saved.last['criticalAlert']! as Map<String, Object?>;

    test('none sound by default', () async {
      platform.access = true;
      await alert.load();

      expect(alert.duringDoNotDisturb, SoundThrough.off);
      expect(
        await alert.previewCritical(chosen),
        contains('Silent mode or Do Not Disturb'),
      );
      expect(
        await alert.preview(chosen),
        contains('Silent mode or Do Not Disturb'),
      );
    });

    test('critical pushes sound with Critical only and the access '
        'given', () async {
      platform.access = true;
      await alert.load();

      final message = await alert.changeDuringDoNotDisturb(
        SoundThrough.critical,
      );

      expect(message, isNull);
      expect(alert.duringDoNotDisturb, SoundThrough.critical);
      expect(criticalAlert()['duringDoNotDisturb'], isTrue);
      expect(platform.saved.last['duringDoNotDisturb'], isFalse);
      expect(await alert.previewCritical(chosen), isNull);
      expect(
        await alert.preview(chosen),
        contains('Silent mode or Do Not Disturb'),
      );
      expect(platform.accessOpened, 0);
    });

    test('every push sounds with All pushes and the access given', () async {
      platform.access = true;
      await alert.load();

      await alert.changeDuringDoNotDisturb(SoundThrough.all);

      expect(criticalAlert()['duringDoNotDisturb'], isTrue);
      expect(platform.saved.last['duringDoNotDisturb'], isTrue);
      expect(await alert.preview(chosen), isNull);
      expect(await alert.previewCritical(chosen), isNull);
    });

    test('without the access, the choice stays Off and the system screen '
        'to give it opens', () async {
      await alert.load();
      final saved = platform.saved.length;

      for (final choice in [SoundThrough.critical, SoundThrough.all]) {
        final message = await alert.changeDuringDoNotDisturb(choice);

        expect(message, contains('Do Not Disturb access'));
      }

      expect(platform.accessOpened, 2);
      expect(alert.quiet.duringDoNotDisturb, SoundThrough.off);
      expect(alert.duringDoNotDisturb, SoundThrough.off);
      expect(platform.saved, hasLength(saved));
    });

    test('the access given in the meantime is read again', () async {
      await alert.load();
      await alert.changeDuringDoNotDisturb(SoundThrough.all);
      platform.access = true;

      await alert.refreshDoNotDisturbAccess();
      await alert.changeDuringDoNotDisturb(SoundThrough.all);

      expect(alert.duringDoNotDisturb, SoundThrough.all);
      expect(platform.accessOpened, 1);
    });

    test('the access taken away shows the choice Off', () async {
      platform.access = true;
      platform.stored = jsonEncode(
        platformAlerts(
          chosen,
          critical,
          quiet.copyWith(duringDoNotDisturb: SoundThrough.critical),
        ),
      );
      await alert.load();
      expect(alert.duringDoNotDisturb, SoundThrough.critical);

      platform.access = false;
      await alert.refreshDoNotDisturbAccess();

      expect(alert.duringDoNotDisturb, SoundThrough.off);
      // Without the access, the phone keeps it quiet.
      expect(
        await alert.previewCritical(chosen),
        contains('Silent mode or Do Not Disturb'),
      );
      // A choice on silent is saved without asking for the access.
      expect(await alert.changeOnSilent(SoundThrough.off), isNull);
      expect(platform.accessOpened, 0);
    });
  });
}
