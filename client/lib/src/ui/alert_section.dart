import 'package:flutter/material.dart';

import '../alert/alert_controller.dart';
import '../alert/alert_settings.dart';

/// The _Alert_ settings: SignalHub's own sound, its volume and its
/// vibration, for pushes the system shows while the app is in the
/// background or closed, and how critical pushes alert. Each change is saved
/// on this device at once and previewed.
class AlertSection extends StatefulWidget {
  const AlertSection({super.key, required this.controller});

  final AlertController controller;

  @override
  State<AlertSection> createState() => _AlertSectionState();
}

class _AlertSectionState extends State<AlertSection> {
  late final AppLifecycleListener _lifecycle;

  AlertController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Do Not Disturb access is given in the phone's settings, which the
    // owner comes back from.
    _lifecycle = AppLifecycleListener(
      onResume: _controller.refreshDoNotDisturbAccess,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _tell(Future<String?> action) async {
    final messenger = ScaffoldMessenger.of(context);
    final message = await action;
    if (message != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final critical = _controller.critical;
      void changeCritical(CriticalAlertSettings next) =>
          _tell(_controller.changeCritical(next));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            title: Text('Alert'),
            subtitle: Text(
              'How pushes sound and vibrate while SignalHub is in the '
              'background or closed, on this device. The phone\'s silent '
              'mode, Do Not Disturb and notification settings still apply, '
              'except as set for critical events below.',
            ),
          ),
          _AlertChoices(
            keyPrefix: 'alert',
            settings: _controller.settings,
            defaultSound: AlertSettings.defaults.sound,
            playTooltip: (sound) => 'Play ${sound.label}',
            change: (next) => _tell(_controller.change(next)),
            preview: (alert) => _tell(_controller.preview(alert)),
          ),
          const ListTile(
            title: Text('Critical events'),
            subtitle: Text('Pushes of events with critical severity.'),
          ),
          SwitchListTile(
            key: const Key('criticalDifferent'),
            title: const Text('Different alert for critical events'),
            subtitle: const Text('Their own sound, volume and vibration'),
            value: critical.different,
            onChanged: (on) => changeCritical(critical.copyWith(different: on)),
          ),
          if (critical.different)
            _AlertChoices(
              keyPrefix: 'critical',
              settings: critical.alert,
              defaultSound: CriticalAlertSettings.defaults.alert.sound,
              playTooltip: (sound) => 'Play ${sound.label} for critical events',
              change: (next) => changeCritical(critical.copyWith(alert: next)),
              preview: (alert) => _tell(_controller.previewCritical(alert)),
            ),
          SwitchListTile(
            key: const Key('criticalOnSilent'),
            title: const Text('Sound when the phone is on silent'),
            subtitle: const Text(
              'Critical events sound and vibrate even when the phone is on '
              'silent or vibrate',
            ),
            value: critical.onSilent,
            onChanged: (on) => changeCritical(critical.copyWith(onSilent: on)),
          ),
          SwitchListTile(
            key: const Key('criticalDuringDoNotDisturb'),
            title: const Text('Sound during Do Not Disturb'),
            subtitle: Text(
              _controller.doNotDisturbAccess
                  ? 'Critical events sound and vibrate during Do Not Disturb'
                  : 'Needs Do Not Disturb access for SignalHub, which '
                        'turning this on asks for',
            ),
            value: _controller.criticalDuringDoNotDisturb,
            onChanged: (on) =>
                changeCritical(critical.copyWith(duringDoNotDisturb: on)),
          ),
        ],
      );
    },
  );
}

/// One alert's sound, volume and vibration.
class _AlertChoices extends StatefulWidget {
  const _AlertChoices({
    required this.keyPrefix,
    required this.settings,
    required this.defaultSound,
    required this.playTooltip,
    required this.change,
    required this.preview,
  });

  /// Tells this alert's widgets apart from another's: `<prefix>Sound-...`.
  final String keyPrefix;
  final AlertSettings settings;
  final AlertSound? defaultSound;
  final String Function(AlertSound) playTooltip;
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
      ],
    );
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
