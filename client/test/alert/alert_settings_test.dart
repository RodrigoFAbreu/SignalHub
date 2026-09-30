import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/alert/alert_settings.dart';

import '../support/fakes.dart';

void main() {
  group('what the platform is given', () {
    test('the defaults: Signal at 80 %, a medium vibration', () {
      expect(AlertSettings.defaults.toPlatform(), {
        'sound': 'signal',
        'volume': 80,
        'vibration': 'medium',
        'pattern': 'standard',
        'length': 'short',
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
        platformAlerts(
          AlertSettings.defaults,
          CriticalAlertSettings.defaults,
          QuietModeSettings.defaults,
        ),
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

    group('the pattern and length', () {
      List<int> timings(AlertPattern pattern, AlertLength length) =>
          AlertSettings.defaults
                  .copyWith(pattern: pattern, length: length)
                  .toPlatform()['timings']!
              as List<int>;
      int lasts(Object? timings) =>
          (timings! as List<int>).fold(0, (sum, t) => sum + t);

      test('by default are the vibration SignalHub always had', () {
        expect(AlertSettings.defaults.pattern, AlertPattern.standard);
        expect(AlertSettings.defaults.length, AlertLength.short);
        expect(timings(AlertPattern.standard, AlertLength.short), [
          0,
          90,
          90,
          90,
          90,
          260,
        ]);
      });

      test('each pattern is its own, and none a single buzz', () {
        final shapes = {
          for (final p in AlertPattern.values)
            timings(p, AlertLength.medium).join(','),
        };

        expect(shapes, hasLength(AlertPattern.values.length));
        expect(timings(AlertPattern.heartbeat, AlertLength.short), [
          0,
          80,
          120,
          200,
        ]);
        expect(timings(AlertPattern.rapid, AlertLength.short), [
          0,
          60,
          60,
          60,
          60,
          60,
          60,
          60,
          60,
          60,
        ]);
        for (final p in AlertPattern.values) {
          if (p == AlertPattern.steady) continue;
          expect(
            timings(p, AlertLength.short).length,
            greaterThan(2),
            reason: p.name,
          );
        }
      });

      test('a longer length repeats the pattern, after its pause', () {
        expect(timings(AlertPattern.standard, AlertLength.medium), [
          0,
          90,
          90,
          90,
          90,
          260,
          400,
          90,
          90,
          90,
          90,
          260,
        ]);
        expect(timings(AlertPattern.heartbeat, AlertLength.medium), [
          0,
          80,
          120,
          200,
          600,
          80,
          120,
          200,
          600,
          80,
          120,
          200,
        ]);
      });

      test('the steady pattern is one buzz as long as the length', () {
        for (final (length, ms) in [
          (AlertLength.short, 600),
          (AlertLength.medium, 2000),
          (AlertLength.long, 5000),
        ]) {
          expect(timings(AlertPattern.steady, length), [0, ms]);
        }
      });

      test('each length lasts about as long as it says', () {
        for (final p in AlertPattern.values) {
          final short = lasts(timings(p, AlertLength.short));
          final medium = lasts(timings(p, AlertLength.medium));
          final long = lasts(timings(p, AlertLength.long));

          expect(short, inInclusiveRange(400, 700), reason: p.name);
          expect(medium, inInclusiveRange(1600, 2500), reason: p.name);
          expect(long, inInclusiveRange(4500, 5500), reason: p.name);
        }
      });

      test('every step works with every pattern and length, and none lasts '
          'longer than 10 s, with amplitude control or without', () {
        for (final p in AlertPattern.values) {
          for (final l in AlertLength.values) {
            final base = AlertSettings.defaults.copyWith(pattern: p, length: l);
            final medium = base.toPlatform();
            for (final (step, amplitude) in [
              (AlertVibration.light, 70),
              (AlertVibration.medium, 160),
              (AlertVibration.strong, 255),
            ]) {
              final platform = base.copyWith(vibration: step).toPlatform();
              final reason = '${p.name} ${l.name} ${step.name}';

              expect(platform['timings'], medium['timings'], reason: reason);
              expect((platform['amplitudes']! as List).toSet(), {
                0,
                amplitude,
              }, reason: reason);
              expect(
                lasts(platform['timings']),
                lessThanOrEqualTo(AlertSettings.longestVibration),
                reason: reason,
              );
              expect(
                lasts(platform['fallbackTimings']),
                lessThanOrEqualTo(AlertSettings.longestVibration),
                reason: reason,
              );
            }
            // Without amplitude control a stronger step buzzes longer, at
            // every length.
            int fallback(AlertVibration v) => lasts(
              base.copyWith(vibration: v).toPlatform()['fallbackTimings'],
            );
            expect(
              fallback(AlertVibration.light),
              lessThan(fallback(AlertVibration.medium)),
            );
            expect(
              fallback(AlertVibration.medium),
              lessThan(fallback(AlertVibration.strong)),
            );
          }
        }
      });

      test('no vibration is nothing, whatever the pattern and length', () {
        final off = AlertSettings.defaults
            .copyWith(
              vibration: AlertVibration.off,
              pattern: AlertPattern.rapid,
              length: AlertLength.long,
            )
            .toPlatform();

        expect(off['timings'], isEmpty);
        expect(off['pattern'], 'rapid');
        expect(off['length'], 'long');
      });
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
        pattern: AlertPattern.heartbeat,
        length: AlertLength.medium,
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
        jsonEncode({
          'sound': 'siren',
          'volume': 'loud',
          'vibration': 'max',
          'pattern': 'morse',
          'length': 'forever',
        }),
      );

      expect(read, AlertSettings.defaults);
      expect(AlertSettings.fromStored('{}'), AlertSettings.defaults);
    });

    test('saved before patterns and lengths, keep the rest and start with '
        'the defaults', () {
      final read = AlertSettings.fromStored(
        jsonEncode({'sound': 'glass', 'volume': 30, 'vibration': 'strong'}),
      );

      expect(
        read,
        const AlertSettings(
          sound: AlertSound.glass,
          volume: 30,
          vibration: AlertVibration.strong,
          pattern: AlertPattern.standard,
          length: AlertLength.short,
        ),
      );
    });
  });

  group('critical pushes', () {
    const general = AlertSettings(
      sound: AlertSound.beacon,
      volume: 50,
      vibration: AlertVibration.light,
    );
    Map<String, Object?> stored(CriticalAlertSettings critical) =>
        platformAlerts(general, critical, QuietModeSettings.defaults);

    test('by default: the general alert', () {
      expect(
        CriticalAlertSettings.defaults.toPlatform(general),
        general.toPlatform(),
      );
    });

    test('by default their own alert is more urgent, louder, stronger, '
        'longer', () {
      const own = CriticalAlertSettings.defaults;

      expect(own.different, isFalse);
      expect(own.alert.sound, AlertSound.urgent);
      expect(own.alert.volume, greaterThan(AlertSettings.defaults.volume));
      expect(
        own.alert.vibration.index,
        greaterThan(AlertSettings.defaults.vibration.index),
      );
      expect(own.alert.pattern, AlertPattern.rapid);
      expect(own.alert.length, AlertLength.long);
    });

    test('with a different alert, play their own', () {
      final critical = CriticalAlertSettings.defaults.copyWith(different: true);

      expect(critical.toPlatform(general), critical.alert.toPlatform());
      expect(critical.toPlatform(general)['resource'], 'signalhub_urgent');
      expect(critical.toPlatform(general)['gain'], 1.0);
      expect(critical.toPlatform(general)['amplitudes'], contains(255));
    });

    test('every other push plays the general alert', () {
      final alerts = stored(
        CriticalAlertSettings.defaults.copyWith(different: true),
      );

      expect(
        {...alerts}
          ..remove('quiet')
          ..remove('critical')
          ..remove('criticalAlert'),
        {
          ...general.toPlatform(),
          'onSilent': false,
          'duringDoNotDisturb': false,
        },
      );
    });

    test('are read back, their own alert kept while not used', () {
      const critical = CriticalAlertSettings(
        different: false,
        alert: AlertSettings(
          sound: AlertSound.glass,
          volume: 60,
          vibration: AlertVibration.off,
          pattern: AlertPattern.steady,
          length: AlertLength.medium,
        ),
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
            'pattern': 'morse',
            'length': 'forever',
          },
        }),
      );

      expect(read, CriticalAlertSettings.defaults);
    });

    test('saved before patterns and lengths, keep the rest and start with '
        'the critical defaults', () {
      final read = CriticalAlertSettings.fromStored(
        jsonEncode({
          'critical': {
            'different': true,
            'sound': 'glass',
            'volume': 60,
            'vibration': 'light',
            'onSilent': false,
            'duringDoNotDisturb': false,
          },
        }),
      );

      expect(read!.different, isTrue);
      expect(
        read.alert,
        const AlertSettings(
          sound: AlertSound.glass,
          volume: 60,
          vibration: AlertVibration.light,
          pattern: AlertPattern.rapid,
          length: AlertLength.long,
        ),
      );
    });
  });

  group('sound on silent and during Do Not Disturb', () {
    const general = AlertSettings(
      sound: AlertSound.beacon,
      volume: 50,
      vibration: AlertVibration.light,
    );

    test('by default: critical pushes on silent, none during Do Not '
        'Disturb', () {
      expect(QuietModeSettings.defaults.onSilent, SoundThrough.critical);
      expect(QuietModeSettings.defaults.duringDoNotDisturb, SoundThrough.off);
    });

    test('each option covers the pushes it names', () {
      expect(SoundThrough.off.covers(critical: false), isFalse);
      expect(SoundThrough.off.covers(critical: true), isFalse);
      expect(SoundThrough.critical.covers(critical: false), isFalse);
      expect(SoundThrough.critical.covers(critical: true), isTrue);
      expect(SoundThrough.all.covers(critical: false), isTrue);
      expect(SoundThrough.all.covers(critical: true), isTrue);
    });

    // Every option on silent, on vibrate and during Do Not Disturb (with
    // and without access), for a normal and a critical push, with and
    // without a different critical alert, as the phone plays them.
    for (final different in [false, true]) {
      for (final onSilent in SoundThrough.values) {
        for (final duringDoNotDisturb in SoundThrough.values) {
          test('different alert ${different ? 'on' : 'off'}, on silent '
              '${onSilent.name}, during Do Not Disturb '
              '${duringDoNotDisturb.name}', () {
            final alerts = platformAlerts(
              general,
              CriticalAlertSettings.defaults.copyWith(different: different),
              QuietModeSettings(
                onSilent: onSilent,
                duringDoNotDisturb: duringDoNotDisturb,
              ),
            );
            for (final critical in [false, true]) {
              final alert = alertForPush(
                alerts,
                critical ? 'CRITICAL' : 'NORMAL',
              );
              final push = critical ? 'a critical push' : 'a normal push';
              final sound = critical && different ? 'urgent' : 'beacon';
              expect(alert['sound'], sound, reason: push);

              final silent = onSilent.covers(critical: critical);
              expect(
                playedOnPhone(alert, ringer: Ringer.silent),
                silent ? (sound: true, vibration: true, alarm: true) : null,
                reason: '$push on silent',
              );
              expect(
                playedOnPhone(alert, ringer: Ringer.vibrate),
                silent
                    ? (sound: true, vibration: true, alarm: true)
                    : (sound: false, vibration: true, alarm: false),
                reason: '$push on vibrate',
              );
              expect(playedOnPhone(alert), (
                sound: true,
                vibration: true,
                alarm: false,
              ), reason: '$push with the ringer on');
              expect(
                playedOnPhone(alert, doNotDisturb: true, access: true),
                duringDoNotDisturb.covers(critical: critical)
                    ? (sound: true, vibration: true, alarm: true)
                    : null,
                reason: '$push during Do Not Disturb',
              );
              expect(
                playedOnPhone(alert, doNotDisturb: true),
                isNull,
                reason: '$push during Do Not Disturb without access',
              );
            }
          });
        }
      }
    }

    test('are read back', () {
      const quiet = QuietModeSettings(
        onSilent: SoundThrough.all,
        duringDoNotDisturb: SoundThrough.critical,
      );
      final alerts = jsonEncode(
        platformAlerts(general, CriticalAlertSettings.defaults, quiet),
      );

      expect(QuietModeSettings.fromStored(alerts), quiet);
    });

    test('carry over the critical switches saved before them', () {
      QuietModeSettings? read(Object? onSilent, Object? duringDoNotDisturb) =>
          QuietModeSettings.fromStored(
            jsonEncode({
              ...general.toPlatform(),
              'critical': {
                'different': false,
                'sound': 'urgent',
                'onSilent': ?onSilent,
                'duringDoNotDisturb': ?duringDoNotDisturb,
              },
            }),
          );

      expect(
        read(true, false),
        const QuietModeSettings(
          onSilent: SoundThrough.critical,
          duringDoNotDisturb: SoundThrough.off,
        ),
      );
      expect(
        read(false, true),
        const QuietModeSettings(
          onSilent: SoundThrough.off,
          duringDoNotDisturb: SoundThrough.critical,
        ),
      );
      expect(read(null, null), QuietModeSettings.defaults);
      expect(read(1, 'yes'), QuietModeSettings.defaults);
    });

    test('none before any were saved', () {
      expect(
        QuietModeSettings.fromStored(jsonEncode(general.toPlatform())),
        isNull,
      );
      expect(QuietModeSettings.fromStored(null), isNull);
      expect(QuietModeSettings.fromStored('not json'), isNull);
    });

    test('values this version does not know are the defaults', () {
      expect(
        QuietModeSettings.fromStored(
          jsonEncode({
            'quiet': {'onSilent': 'sometimes', 'duringDoNotDisturb': true},
          }),
        ),
        QuietModeSettings.defaults,
      );
    });
  });
}
