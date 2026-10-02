import 'package:flutter/material.dart';

import '../alert/alert_controller.dart';
import '../alert/alert_settings.dart';

/// Says what the owner is to know about an alert setting that was not
/// saved, or a preview the phone kept quiet.
Future<void> _tell(BuildContext context, Future<String?> action) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = await action;
  if (message != null) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The _Alert_ settings: SignalHub's own sound, its volume and its
/// vibration (its strength, pattern and length), for every push, the app
/// open, in the background or closed; which pushes sound
/// on silent and during Do Not Disturb; and whether critical events have an
/// alert of their own, set in [CriticalAlertSection] below this. Each
/// change is saved on this device at once and previewed.
class GeneralAlertSection extends StatelessWidget {
  const GeneralAlertSection({super.key, required this.controller});

  final AlertController controller;

  /// One line for the folded group, such as _Signal · 80 % · Medium ·
  /// Short, short, long · Short · sounds on silent: critical_.
  static String summary(AlertController controller) => [
    alertSummary(controller.settings),
    if (controller.quiet.onSilent != SoundThrough.off)
      'sounds on silent: ${_quietSummary(controller.quiet.onSilent)}',
    if (controller.duringDoNotDisturb != SoundThrough.off)
      'during Do Not Disturb: '
          '${_quietSummary(controller.duringDoNotDisturb)}',
  ].join(' · ');

  /// One alert's sound, volume and vibration in a line, such as _Signal ·
  /// 80 % · Medium · Short, short, long · Short_.
  static String alertSummary(AlertSettings alert) => [
    alert.sound?.label ?? 'No sound',
    if (alert.sound != null) '${alert.volume} %',
    if (alert.vibration == AlertVibration.off)
      'No vibration'
    else ...[
      alert.vibration.label,
      alert.pattern.label,
      alert.length.label,
    ],
  ].join(' · ');

  static String _quietSummary(SoundThrough through) => switch (through) {
    SoundThrough.off => 'off',
    SoundThrough.critical => 'critical',
    SoundThrough.all => 'all pushes',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final critical = controller.critical;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            subtitle: Text(
              'How pushes sound and vibrate on this device, whether '
              'SignalHub is open or not. The phone\'s silent '
              'mode, Do Not Disturb and notification settings still apply, '
              'except as chosen below.',
            ),
          ),
          _AlertChoices(
            keyPrefix: 'alert',
            settings: controller.settings,
            defaultSound: AlertSettings.defaults.sound,
            playTooltip: (sound) => 'Play ${sound.label}',
            vibrateTooltip: (pattern) => 'Vibrate ${pattern.label}',
            change: (next) => _tell(context, controller.change(next)),
            preview: (alert) => _tell(context, controller.preview(alert)),
          ),
          _QuietChoice(
            key: const Key('soundOnSilent'),
            title: 'Sound when the phone is on silent',
            description:
                'These pushes sound and vibrate as an alarm, at the alarm '
                'volume, while the phone is on silent or vibrate',
            value: controller.quiet.onSilent,
            change: (next) => _tell(context, controller.changeOnSilent(next)),
          ),
          _QuietChoice(
            key: const Key('soundDuringDoNotDisturb'),
            title: 'Sound during Do Not Disturb',
            description: controller.doNotDisturbAccess
                ? 'These pushes sound and vibrate as an alarm, at the alarm '
                      'volume, during Do Not Disturb'
                : 'Needs Do Not Disturb access for SignalHub, which '
                      'choosing Critical only or All pushes asks for',
            value: controller.duringDoNotDisturb,
            change: (next) =>
                _tell(context, controller.changeDuringDoNotDisturb(next)),
          ),
          SwitchListTile(
            key: const Key('criticalDifferent'),
            title: const Text('Different alert for critical events'),
            subtitle: const Text(
              'Their own sound, volume, vibration, pattern and length, set '
              'under Critical alert',
            ),
            value: critical.different,
            onChanged: (on) => _tell(
              context,
              controller.changeCritical(critical.copyWith(different: on)),
            ),
          ),
        ],
      );
    },
  );
}

/// Which pushes sound through one of the phone's quiet modes: none, critical
/// ones only, or all.
class _QuietChoice extends StatelessWidget {
  const _QuietChoice({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.change,
  });

  final String title;
  final String description;
  final SoundThrough value;
  final void Function(SoundThrough) change;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(title: Text(title), subtitle: Text(description)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<SoundThrough>(
          showSelectedIcon: false,
          segments: [
            for (final through in SoundThrough.values)
              ButtonSegment(value: through, label: Text(through.label)),
          ],
          selected: {value},
          onSelectionChanged: (selected) => change(selected.single),
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}

/// The _Critical alert_ settings, used once **Different alert for critical
/// events** is on: the sound, volume and vibration pushes of critical events
/// play instead of the general alert. Saved on this device at every change.
class CriticalAlertSection extends StatelessWidget {
  const CriticalAlertSection({super.key, required this.controller});

  final AlertController controller;

  /// One line for the folded sub-group, such as _Urgent · 100 % · Strong ·
  /// Rapid pulse · Long_, or _Same as Alert_ while critical events play the
  /// general alert.
  static String summary(AlertController controller) {
    final critical = controller.critical;
    return critical.different
        ? GeneralAlertSection.alertSummary(critical.alert)
        : 'Same as Alert';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final critical = controller.critical;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            subtitle: Text(
              'Pushes of events with critical severity play this alert '
              'instead of the one above.',
            ),
          ),
          _AlertChoices(
            keyPrefix: 'critical',
            settings: critical.alert,
            defaultSound: CriticalAlertSettings.defaults.alert.sound,
            playTooltip: (sound) => 'Play ${sound.label} for critical events',
            vibrateTooltip: (pattern) =>
                'Vibrate ${pattern.label} for critical events',
            change: (next) => _tell(
              context,
              controller.changeCritical(critical.copyWith(alert: next)),
            ),
            preview: (alert) =>
                _tell(context, controller.previewCritical(alert)),
          ),
        ],
      );
    },
  );
}

/// One alert's sound, volume and vibration: its strength, pattern and
/// length.
class _AlertChoices extends StatefulWidget {
  const _AlertChoices({
    required this.keyPrefix,
    required this.settings,
    required this.defaultSound,
    required this.playTooltip,
    required this.vibrateTooltip,
    required this.change,
    required this.preview,
  });

  /// Tells this alert's widgets apart from another's: `<prefix>Sound-...`.
  final String keyPrefix;
  final AlertSettings settings;
  final AlertSound? defaultSound;
  final String Function(AlertSound) playTooltip;
  final String Function(AlertPattern) vibrateTooltip;
  final void Function(AlertSettings) change;
  final void Function(AlertSettings) preview;

  @override
  State<_AlertChoices> createState() => _AlertChoicesState();
}

class _AlertChoicesState extends State<_AlertChoices> {
  /// The volume while the slider is dragged; saved when it is let go.
  int? _dragged;

  static const _none = 'none';

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final prefix = widget.keyPrefix;
    final volume = _dragged ?? settings.volume;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Label('Sound'),
        RadioGroup<String>(
          groupValue: settings.sound?.name ?? _none,
          onChanged: (name) => widget.change(
            settings.copyWith(sound: () => AlertSound.parse(name)),
          ),
          child: Column(
            children: [
              for (final sound in AlertSound.values)
                RadioListTile<String>(
                  key: Key('${prefix}Sound-${sound.name}'),
                  value: sound.name,
                  title: Text(
                    sound == widget.defaultSound
                        ? '${sound.label} (default)'
                        : sound.label,
                  ),
                  secondary: IconButton(
                    key: Key('${prefix}Play-${sound.name}'),
                    tooltip: widget.playTooltip(sound),
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () => widget.preview(
                      settings.copyWith(
                        sound: () => sound,
                        vibration: AlertVibration.off,
                      ),
                    ),
                  ),
                ),
              RadioListTile<String>(
                key: Key('${prefix}Sound-none'),
                value: _none,
                title: const Text('None'),
              ),
            ],
          ),
        ),
        const _Label('Volume'),
        Slider(
          key: Key('${prefix}Volume'),
          min: AlertSettings.minVolume.toDouble(),
          max: AlertSettings.maxVolume.toDouble(),
          divisions:
              (AlertSettings.maxVolume - AlertSettings.minVolume) ~/
              AlertSettings.volumeStep,
          value: volume.toDouble(),
          label: '$volume %',
          semanticFormatterCallback: (value) => '${value.round()} %',
          onChanged: settings.sound == null
              ? null
              : (value) =>
                    setState(() => _dragged = AlertSettings.clampVolume(value)),
          onChangeEnd: settings.sound == null
              ? null
              : (value) {
                  setState(() => _dragged = null);
                  widget.change(
                    settings.copyWith(volume: AlertSettings.clampVolume(value)),
                  );
                },
        ),
        const _Label('Vibration'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<AlertVibration>(
            key: Key('${prefix}Vibration'),
            showSelectedIcon: false,
            segments: [
              for (final v in AlertVibration.values)
                ButtonSegment(value: v, label: Text(v.label)),
            ],
            selected: {settings.vibration},
            onSelectionChanged: (selected) =>
                widget.change(settings.copyWith(vibration: selected.single)),
          ),
        ),
        ..._vibrationShape(settings),
      ],
    );
  }

  /// The vibration's pattern and length, previewed as they are chosen, and
  /// greyed while it is off.
  List<Widget> _vibrationShape(AlertSettings settings) {
    final prefix = widget.keyPrefix;
    final vibrates = settings.vibration != AlertVibration.off;
    return [
      const _Label('Pattern'),
      RadioGroup<AlertPattern>(
        groupValue: settings.pattern,
        onChanged: (pattern) =>
            widget.change(settings.copyWith(pattern: pattern)),
        child: Column(
          children: [
            for (final pattern in AlertPattern.values)
              RadioListTile<AlertPattern>(
                key: Key('${prefix}Pattern-${pattern.name}'),
                value: pattern,
                enabled: vibrates,
                title: Text(pattern.label),
                secondary: IconButton(
                  key: Key('${prefix}Vibrate-${pattern.name}'),
                  tooltip: widget.vibrateTooltip(pattern),
                  icon: const Icon(Icons.vibration),
                  onPressed: vibrates
                      ? () => widget.preview(
                          settings.copyWith(
                            sound: () => null,
                            pattern: pattern,
                          ),
                        )
                      : null,
                ),
              ),
          ],
        ),
      ),
      const _Label('Length'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<AlertLength>(
          key: Key('${prefix}Length'),
          showSelectedIcon: false,
          segments: [
            for (final l in AlertLength.values)
              ButtonSegment(value: l, label: Text(l.label), enabled: vibrates),
          ],
          selected: {settings.length},
          onSelectionChanged: (selected) =>
              widget.change(settings.copyWith(length: selected.single)),
        ),
      ),
    ];
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(text, style: Theme.of(context).textTheme.labelLarge),
  );
}
