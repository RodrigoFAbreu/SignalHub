import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/alert/alert_settings.dart';

void main() {
  group('what the platform is given', () {
    test('the defaults: Signal at 80 %, a medium vibration', () {
      expect(AlertSettings.defaults.toPlatform(), {
        'sound': 'signal',
        'volume': 80,
        'vibration': 'medium',
        'resource': 'signalhub_signal',
        'gain': 0.8,
        'timings': [0, 90, 90, 90, 90, 260],
        'amplitudes': [0, 160, 0, 160, 0, 160],
        'fallbackTimings': [0, 90, 90, 90, 90, 260],
      });
    });

    test('are what Android plays before the app saved any settings', () {
      final bundled = File(
        'android/app/src/main/res/raw/signalhub_alert_defaults.json',
      );

      expect(
        jsonDecode(bundled.readAsStringSync()),
        platformAlerts(AlertSettings.defaults, CriticalAlertSettings.defaults),
      );
    });

    test('each sound is a bundled resource', () {
      for (final sound in AlertSound.values) {
        final settings = AlertSettings.defaults.copyWith(sound: () => sound);
        final resource = settings.toPlatform()['resource'];

        expect(resource, 'signalhub_${sound.name}');
        expect(
          File('android/app/src/main/res/raw/$resource.wav').existsSync(),
          isTrue,
          reason: '$resource.wav',
        );
      }
    });

    test('no sound is no resource', () {
      final none = AlertSettings.defaults.copyWith(sound: () => null);

      expect(none.toPlatform(), containsPair('sound', null));
      expect(none.toPlatform(), containsPair('resource', null));
    });

    test('the volume is a gain from 0.1 to 1', () {
      for (final (volume, gain) in [(10, 0.1), (50, 0.5), (100, 1.0)]) {
        final settings = AlertSettings.defaults.copyWith(volume: volume);

        expect(settings.toPlatform()['gain'], gain);
      }
    });

    test('the steps change the amplitude, or the length without it', () {
      Map<String, Object?> platform(AlertVibration vibration) =>
          AlertSettings.defaults.copyWith(vibration: vibration).toPlatform();

      expect(platform(AlertVibration.light)['amplitudes'], [
        0,
        70,
        0,
        70,
        0,
        70,
      ]);
      expect(platform(AlertVibration.strong)['amplitudes'], [
        0,
        255,
        0,
        255,
        0,
        255,
      ]);
      // The pattern is the same; only the buzzes, not the pauses, change.
      for (final v in [AlertVibration.light, AlertVibration.strong]) {
        expect(platform(v)['timings'], [0, 90, 90, 90, 90, 260]);
      }
      expect(platform(AlertVibration.light)['fallbackTimings'], [
        0,
        45,
        90,
        45,
        90,
        130,
      ]);
      expect(platform(AlertVibration.strong)['fallbackTimings'], [
        0,
        153,
        90,
        153,
        90,
        442,
      ]);
    });

    test('no vibration is an empty pattern', () {
      final off = AlertSettings.defaults
          .copyWith(vibration: AlertVibration.off)
          .toPlatform();

      expect(off['timings'], isEmpty);
      expect(off['amplitudes'], isEmpty);
      expect(off['fallbackTimings'], isEmpty);
    });
  });

  group('the volume', () {
    test('is kept within 10 % to 100 %, in steps of 10', () {
      expect(AlertSettings.clampVolume(0), 10);
      expect(AlertSettings.clampVolume(44.9), 40);
      expect(AlertSettings.clampVolume(45), 50);
      expect(AlertSettings.clampVolume(130), 100);
    });
  });

  group('stored settings', () {
    test('are read back', () {
      const settings = AlertSettings(
        sound: AlertSound.glass,
        volume: 30,
        vibration: AlertVibration.strong,
      );

      expect(
        AlertSettings.fromStored(jsonEncode(settings.toPlatform())),
        settings,
      );
    });

    test('keep no sound', () {
      final none = AlertSettings.defaults.copyWith(sound: () => null);

      expect(AlertSettings.fromStored(jsonEncode(none.toPlatform())), none);
    });

    test('none or unreadable are no settings', () {
      expect(AlertSettings.fromStored(null), isNull);
      expect(AlertSettings.fromStored('not json'), isNull);
      expect(AlertSettings.fromStored('[1]'), isNull);
    });

    test('values this version does not know are the defaults', () {
      final read = AlertSettings.fromStored(
        jsonEncode({'sound': 'siren', 'volume': 'loud', 'vibration': 'max'}),
      );

      expect(read, AlertSettings.defaults);
      expect(AlertSettings.fromStored('{}'), AlertSettings.defaults);
    });
  });

  group('critical pushes', () {
    const general = AlertSettings(
      sound: AlertSound.beacon,
      volume: 50,
      vibration: AlertVibration.light,
    );
    Map<String, Object?> stored(CriticalAlertSettings critical) =>
        platformAlerts(general, critical);

    test('by default: the general alert, sounding on silent only', () {
      expect(CriticalAlertSettings.defaults.toPlatform(general), {
        ...general.toPlatform(),
        'onSilent': true,
        'duringDoNotDisturb': false,
      });
    });

    test('by default their own alert is more urgent, louder, stronger', () {
      const own = CriticalAlertSettings.defaults;

      expect(own.different, isFalse);
      expect(own.alert.sound, AlertSound.urgent);
      expect(own.alert.volume, greaterThan(AlertSettings.defaults.volume));
      expect(
        own.alert.vibration.index,
        greaterThan(AlertSettings.defaults.vibration.index),
      );
    });

    test('with a different alert, play their own', () {
      final critical = CriticalAlertSettings.defaults.copyWith(different: true);

      expect(critical.toPlatform(general), {
        ...critical.alert.toPlatform(),
        'onSilent': true,
        'duringDoNotDisturb': false,
      });
      expect(critical.toPlatform(general)['resource'], 'signalhub_urgent');
      expect(critical.toPlatform(general)['gain'], 1.0);
      expect(critical.toPlatform(general)['amplitudes'], contains(255));
    });

    test('each switch is given as it is set', () {
      for (final onSilent in [false, true]) {
        for (final duringDoNotDisturb in [false, true]) {
          final alert = CriticalAlertSettings.defaults
              .copyWith(
                onSilent: onSilent,
                duringDoNotDisturb: duringDoNotDisturb,
              )
              .toPlatform(general);

          expect(alert['onSilent'], onSilent);
          expect(alert['duringDoNotDisturb'], duringDoNotDisturb);
        }
      }
    });

    test('every other push plays the general alert, never on silent', () {
      final alerts = stored(
        CriticalAlertSettings.defaults.copyWith(
          different: true,
          duringDoNotDisturb: true,
        ),
      );

      expect(
        {...alerts}
          ..remove('critical')
          ..remove('criticalAlert'),
        {...general.toPlatform()},
      );
      expect(alerts, isNot(contains('onSilent')));
      expect(alerts, isNot(contains('duringDoNotDisturb')));
    });

    test('are read back, their own alert kept while not used', () {
      const critical = CriticalAlertSettings(
        different: false,
        alert: AlertSettings(
          sound: AlertSound.glass,
          volume: 60,
          vibration: AlertVibration.off,
        ),
        onSilent: false,
        duringDoNotDisturb: true,
      );

      expect(
        CriticalAlertSettings.fromStored(jsonEncode(stored(critical))),
        critical,
      );
      expect(AlertSettings.fromStored(jsonEncode(stored(critical))), general);
    });

    test('none next to a general alert saved before them', () {
      expect(
        CriticalAlertSettings.fromStored(jsonEncode(general.toPlatform())),
        isNull,
      );
      expect(CriticalAlertSettings.fromStored(null), isNull);
      expect(CriticalAlertSettings.fromStored('not json'), isNull);
    });

    test('values this version does not know are the defaults', () {
      final read = CriticalAlertSettings.fromStored(
        jsonEncode({
          'critical': {
            'different': 'yes',
            'sound': 'siren',
            'volume': 'loud',
            'vibration': 'max',
            'onSilent': 1,
          },
        }),
      );

      expect(read, CriticalAlertSettings.defaults);
    });
  });
}
