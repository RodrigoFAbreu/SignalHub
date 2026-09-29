import 'dart:convert';
import 'dart:math';

/// SignalHub's own notification sounds, bundled with the app
/// (`client/sounds/`).
enum AlertSound {
  signal('Signal'),
  beacon('Beacon'),
  pulse('Pulse'),
  glass('Glass'),
  urgent('Urgent');

  const AlertSound(this.label);

  final String label;

  /// The Android raw resource the sound is played from.
  String get resource => 'signalhub_$name';

  static AlertSound? parse(Object? name) =>
      values.where((s) => s.name == name).firstOrNull;
}

/// How strongly the alert vibrates.
enum AlertVibration {
  off('Off'),
  light('Light'),
  medium('Medium'),
  strong('Strong');

  const AlertVibration(this.label);

  final String label;

  static AlertVibration? parse(Object? name) =>
      values.where((v) => v.name == name).firstOrNull;
}

/// The rhythm of the alert's vibration, SignalHub's own: each unlike the
/// others and unlike the phone's single buzz.
enum AlertPattern {
  // Milliseconds, alternately on and off, starting with a buzz; the gap is
  // the pause before each repeat.
  standard('Short, short, long', [90, 90, 90, 90, 260], gap: 400),
  steady('Steady', [100], gap: 0),
  heartbeat('Heartbeat', [80, 120, 200], gap: 600),
  rapid('Rapid pulse', [60, 60, 60, 60, 60, 60, 60, 60, 60], gap: 120);

  const AlertPattern(this.label, this.buzzes, {required this.gap});

  final String label;
  final List<int> buzzes;
  final int gap;

  int get _duration => buzzes.fold(0, (sum, t) => sum + t);

  static AlertPattern? parse(Object? name) =>
      values.where((p) => p.name == name).firstOrNull;
}

/// About how long the alert vibrates, by repeating its pattern.
enum AlertLength {
  short('Short', 600),
  medium('Medium', 2000),
  long('Long', 5000);

  const AlertLength(this.label, this.milliseconds);

  final String label;

  /// The length aimed at; the pattern repeats whole, so it comes near it.
  final int milliseconds;

  static AlertLength? parse(Object? name) =>
      values.where((l) => l.name == name).firstOrNull;
}

/// How this installation alerts the owner to a push shown by the system:
/// SignalHub's own sound, at a volume, and its own vibration, in a pattern
/// and of a length. Kept on the device, never on the server.
class AlertSettings {
  const AlertSettings({
    required this.sound,
    required this.volume,
    required this.vibration,
    this.pattern = AlertPattern.standard,
    this.length = AlertLength.short,
  });

  static const defaults = AlertSettings(
    sound: AlertSound.signal,
    volume: 80,
    vibration: AlertVibration.medium,
    pattern: AlertPattern.standard,
    length: AlertLength.short,
  );

  /// No vibration lasts longer, whatever its pattern, length and step, in
  /// milliseconds.
  static const longestVibration = 10000;

  /// The volume slider's range and step, in percent. No sound at all is
  /// [sound] `null`, not a volume of zero.
  static const minVolume = 10;
  static const maxVolume = 100;
  static const volumeStep = 10;

  /// The sound played, or `null` for none.
  final AlertSound? sound;

  /// The sound's loudness in percent of the phone's notification volume,
  /// from [minVolume] to [maxVolume] in steps of [volumeStep].
  final int volume;

  /// How strongly it vibrates.
  final AlertVibration vibration;

  final AlertPattern pattern;
  final AlertLength length;

  AlertSettings copyWith({
    AlertSound? Function()? sound,
    int? volume,
    AlertVibration? vibration,
    AlertPattern? pattern,
    AlertLength? length,
  }) => AlertSettings(
    sound: sound == null ? this.sound : sound(),
    volume: volume == null ? this.volume : clampVolume(volume),
    vibration: vibration ?? this.vibration,
    pattern: pattern ?? this.pattern,
    length: length ?? this.length,
  );

  /// [volume] within the slider's range, rounded to its steps.
  static int clampVolume(num volume) =>
      ((volume.clamp(minVolume, maxVolume) / volumeStep).round() * volumeStep)
          .toInt();

  /// The settings a platform stored, or `null` when there are none. Values
  /// this version does not know fall back to the defaults one by one.
  static AlertSettings? fromStored(String? stored) {
    final json = _decode(stored);
    return json == null ? null : fromJson(json);
  }

  /// The settings in [json] (sound, volume, vibration, pattern and length,
  /// as [toPlatform] gives them); what is missing or unknown is
  /// [fallback]'s, so settings saved before patterns and lengths keep
  /// [fallback]'s.
  static AlertSettings fromJson(
    Map<String, Object?> json, {
    AlertSettings fallback = defaults,
  }) {
    final sound = json['sound'];
    final volume = json['volume'];
    return AlertSettings(
      sound: !json.containsKey('sound')
          ? fallback.sound
          : sound == null
          ? null
          : AlertSound.parse(sound) ?? fallback.sound,
      volume: volume is num ? clampVolume(volume) : fallback.volume,
      vibration: AlertVibration.parse(json['vibration']) ?? fallback.vibration,
      pattern: AlertPattern.parse(json['pattern']) ?? fallback.pattern,
      length: AlertLength.parse(json['length']) ?? fallback.length,
    );
  }

  /// What the platform is given and stores (`AlertPlatform`): these
  /// settings, to read them back, and what to play from them, so the native
  /// code plays exactly this without knowing the settings.
  ///
  /// `resource` is the raw sound resource, or `null` for none; `gain` its
  /// volume from 0 to 1. `timings` (milliseconds, alternately off and on,
  /// starting with off) and `amplitudes` (1 to 255 while on) are the
  /// vibration of a phone with amplitude control; `fallbackTimings` the
  /// vibration of one without, where the steps change the length of each
  /// buzz instead. Both are empty when the vibration is off, and are the
  /// [pattern] repeated to about the [length].
  Map<String, Object?> toPlatform() {
    final buzzes = vibration == AlertVibration.off ? const <int>[] : _timings;
    return {
      'sound': sound?.name,
      'volume': volume,
      'vibration': vibration.name,
      'pattern': pattern.name,
      'length': length.name,
      'resource': sound?.resource,
      'gain': volume / 100,
      'timings': buzzes,
      'amplitudes': [
        for (final (i, _) in buzzes.indexed)
          i.isOdd ? _amplitudes[vibration]! : 0,
      ],
      'fallbackTimings': [
        for (final (i, t) in buzzes.indexed)
          i.isOdd ? (t * _lengths[vibration]!).round() : t,
      ],
    };
  }

  /// The [pattern], repeated whole as often as comes nearest the [length]
  /// and at least once. Milliseconds, alternately off and on, starting with
  /// off; a pattern without a gap runs on as one buzz.
  List<int> get _timings {
    final gap = pattern.gap;
    final repeats = max(
      1,
      ((length.milliseconds + gap) / (pattern._duration + gap)).round(),
    );
    final timings = [0, ...pattern.buzzes];
    for (var r = 1; r < repeats; r++) {
      if (gap == 0) {
        timings.last += pattern.buzzes.first;
        timings.addAll(pattern.buzzes.skip(1));
      } else {
        timings.addAll([gap, ...pattern.buzzes]);
      }
    }
    return timings;
  }

  static const _amplitudes = {
    AlertVibration.light: 70,
    AlertVibration.medium: 160,
    AlertVibration.strong: 255,
  };

  /// Without amplitude control, a stronger step buzzes longer.
  static const _lengths = {
    AlertVibration.light: 0.5,
    AlertVibration.medium: 1.0,
    AlertVibration.strong: 1.7,
  };

  @override
  bool operator ==(Object other) =>
      other is AlertSettings &&
      other.sound == sound &&
      other.volume == volume &&
      other.vibration == vibration &&
      other.pattern == pattern &&
      other.length == length;

  @override
  int get hashCode => Object.hash(sound, volume, vibration, pattern, length);

  @override
  String toString() =>
      'AlertSettings(${sound?.name ?? 'none'}, '
      '$volume %, ${vibration.name}, ${pattern.name}, ${length.name})';
}

/// How a push of severity `CRITICAL` alerts, whatever its producer or
/// category. A critical push plays the general alert ([AlertSettings]),
/// or [alert] when [different]; either way, [onSilent] and
/// [duringDoNotDisturb] decide whether it sounds when the phone is on silent
/// or vibrate, and during Do Not Disturb. Kept on the device, never on the
/// server.
class CriticalAlertSettings {
  const CriticalAlertSettings({
    required this.different,
    required this.alert,
    required this.onSilent,
    required this.duringDoNotDisturb,
  });

  /// The same alert as every other push, but sounding on silent; more
  /// urgent, louder, stronger and longer than the general alert once
  /// [different].
  static const defaults = CriticalAlertSettings(
    different: false,
    alert: AlertSettings(
      sound: AlertSound.urgent,
      volume: 100,
      vibration: AlertVibration.strong,
      pattern: AlertPattern.rapid,
      length: AlertLength.long,
    ),
    onSilent: true,
    duringDoNotDisturb: false,
  );

  /// Whether critical pushes play [alert] instead of the general alert.
  final bool different;

  /// Critical pushes' own sound, volume and vibration, kept while
  /// [different] is off.
  final AlertSettings alert;

  /// Whether a critical push sounds and vibrates while the phone's ringer
  /// is on silent or vibrate.
  final bool onSilent;

  /// Whether a critical push sounds and vibrates during Do Not Disturb,
  /// which Android allows only with the app's Do Not Disturb access.
  final bool duringDoNotDisturb;

  CriticalAlertSettings copyWith({
    bool? different,
    AlertSettings? alert,
    bool? onSilent,
    bool? duringDoNotDisturb,
  }) => CriticalAlertSettings(
    different: different ?? this.different,
    alert: alert ?? this.alert,
    onSilent: onSilent ?? this.onSilent,
    duringDoNotDisturb: duringDoNotDisturb ?? this.duringDoNotDisturb,
  );

  /// The settings a platform stored with [platformAlerts], or `null` when
  /// there are none (also when only a general alert was stored, by a
  /// version without these). Values this version does not know fall back
  /// to the defaults one by one.
  static CriticalAlertSettings? fromStored(String? stored) {
    final json = _decode(stored)?['critical'];
    if (json is! Map<String, Object?>) return null;
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key]! as bool : fallback;
    return CriticalAlertSettings(
      different: flag('different', defaults.different),
      alert: AlertSettings.fromJson(json, fallback: defaults.alert),
      onSilent: flag('onSilent', defaults.onSilent),
      duringDoNotDisturb: flag(
        'duringDoNotDisturb',
        defaults.duringDoNotDisturb,
      ),
    );
  }

  /// These settings as stored, to read them back.
  Map<String, Object?> toStored() => {
    'different': different,
    'sound': alert.sound?.name,
    'volume': alert.volume,
    'vibration': alert.vibration.name,
    'pattern': alert.pattern.name,
    'length': alert.length.name,
    'onSilent': onSilent,
    'duringDoNotDisturb': duringDoNotDisturb,
  };

  /// What a critical push plays, with [general] the general alert: the
  /// alert's [AlertSettings.toPlatform], and `onSilent` and
  /// `duringDoNotDisturb`, which the platform reads as `false` in the
  /// general alert's.
  Map<String, Object?> toPlatform(AlertSettings general) => {
    ...(different ? alert : general).toPlatform(),
    'onSilent': onSilent,
    'duringDoNotDisturb': duringDoNotDisturb,
  };

  @override
  bool operator ==(Object other) =>
      other is CriticalAlertSettings &&
      other.different == different &&
      other.alert == alert &&
      other.onSilent == onSilent &&
      other.duringDoNotDisturb == duringDoNotDisturb;

  @override
  int get hashCode =>
      Object.hash(different, alert, onSilent, duringDoNotDisturb);

  @override
  String toString() =>
      'CriticalAlertSettings(different: $different, $alert, '
      'onSilent: $onSilent, duringDoNotDisturb: $duringDoNotDisturb)';
}

/// What the platform stores (`AlertPlatform.save`): the [general] alert's
/// [AlertSettings.toPlatform], played for every push but a critical one, as
/// before critical pushes had their own; `critical`, the [critical]
/// settings to read them back; and `criticalAlert`, what a push of severity
/// `CRITICAL` plays.
Map<String, Object?> platformAlerts(
  AlertSettings general,
  CriticalAlertSettings critical,
) => {
  ...general.toPlatform(),
  'critical': critical.toStored(),
  'criticalAlert': critical.toPlatform(general),
};

Map<String, Object?>? _decode(String? stored) {
  if (stored == null) return null;
  final Object? json;
  try {
    json = jsonDecode(stored);
  } on FormatException {
    return null;
  }
  return json is Map<String, Object?> ? json : null;
}
