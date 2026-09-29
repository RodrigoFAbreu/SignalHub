import 'dart:convert';

/// SignalHub's own notification sounds, bundled with the app
/// (`client/sounds/`).
enum AlertSound {
  signal('Signal'),
  beacon('Beacon'),
  pulse('Pulse'),
  glass('Glass');

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

/// How this installation alerts the owner to a push shown by the system:
/// SignalHub's own sound, at a volume, and its own vibration. Kept on the
/// device, never on the server.
class AlertSettings {
  const AlertSettings({
    required this.sound,
    required this.volume,
    required this.vibration,
  });

  static const defaults = AlertSettings(
    sound: AlertSound.signal,
    volume: 80,
    vibration: AlertVibration.medium,
  );

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

  final AlertVibration vibration;

  AlertSettings copyWith({
    AlertSound? Function()? sound,
    int? volume,
    AlertVibration? vibration,
  }) => AlertSettings(
    sound: sound == null ? this.sound : sound(),
    volume: volume == null ? this.volume : clampVolume(volume),
    vibration: vibration ?? this.vibration,
  );

  /// [volume] within the slider's range, rounded to its steps.
  static int clampVolume(num volume) =>
      ((volume.clamp(minVolume, maxVolume) / volumeStep).round() * volumeStep)
          .toInt();

  /// The settings a platform stored, or `null` when there are none. Values
  /// this version does not know fall back to the defaults one by one.
  static AlertSettings? fromStored(String? stored) {
    if (stored == null) return null;
    final Object? json;
    try {
      json = jsonDecode(stored);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final sound = json['sound'];
    final volume = json['volume'];
    return AlertSettings(
      sound: !json.containsKey('sound')
          ? defaults.sound
          : sound == null
          ? null
          : AlertSound.parse(sound) ?? defaults.sound,
      volume: volume is num ? clampVolume(volume) : defaults.volume,
      vibration: AlertVibration.parse(json['vibration']) ?? defaults.vibration,
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
  /// buzz instead. Both are empty when the vibration is off.
  Map<String, Object?> toPlatform() {
    final buzzes = vibration == AlertVibration.off ? const <int>[] : _pattern;
    return {
      'sound': sound?.name,
      'volume': volume,
      'vibration': vibration.name,
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

  /// SignalHub's vibration: two short buzzes and a long one, unlike the
  /// phone's single buzz. Milliseconds, alternately off and on.
  static const _pattern = [0, 90, 90, 90, 90, 260];

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
      other.vibration == vibration;

  @override
  int get hashCode => Object.hash(sound, volume, vibration);

  @override
  String toString() =>
      'AlertSettings(${sound?.name ?? 'none'}, '
      '$volume %, ${vibration.name})';
}
