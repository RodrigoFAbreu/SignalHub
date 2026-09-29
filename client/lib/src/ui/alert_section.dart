import 'package:flutter/material.dart';

import '../alert/alert_controller.dart';
import '../alert/alert_settings.dart';

/// The _Alert_ settings: SignalHub's own sound, its volume and its
/// vibration, for pushes the system shows while the app is in the
/// background or closed. Each change is saved on this device at once and
/// previewed.
class AlertSection extends StatefulWidget {
  const AlertSection({super.key, required this.controller});

  final AlertController controller;

  @override
  State<AlertSection> createState() => _AlertSectionState();
}

class _AlertSectionState extends State<AlertSection> {
  /// The volume while the slider is dragged; saved when it is let go.
  int? _dragged;

  AlertController get _controller => widget.controller;

  static const _none = 'none';

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
      final settings = _controller.settings;
      final volume = _dragged ?? settings.volume;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListTile(
            title: Text('Alert'),
            subtitle: Text(
              'How pushes sound and vibrate while SignalHub is in the '
              'background or closed, on this device. The phone\'s silent '
              'mode, Do Not Disturb and notification settings still apply.',
            ),
          ),
          const _Label('Sound'),
          RadioGroup<String>(
            groupValue: settings.sound?.name ?? _none,
            onChanged: (name) => _tell(
              _controller.change(
                settings.copyWith(sound: () => AlertSound.parse(name)),
              ),
            ),
            child: Column(
              children: [
                for (final sound in AlertSound.values)
                  RadioListTile<String>(
                    key: Key('alertSound-${sound.name}'),
                    value: sound.name,
                    title: Text(
                      sound == AlertSettings.defaults.sound
                          ? '${sound.label} (default)'
                          : sound.label,
                    ),
                    secondary: IconButton(
                      key: Key('alertPlay-${sound.name}'),
                      tooltip: 'Play ${sound.label}',
                      icon: const Icon(Icons.play_arrow),
                      onPressed: () => _tell(
                        _controller.preview(
                          settings.copyWith(
                            sound: () => sound,
                            vibration: AlertVibration.off,
                          ),
                        ),
                      ),
                    ),
                  ),
                const RadioListTile<String>(
                  key: Key('alertSound-none'),
                  value: _none,
                  title: Text('None'),
                ),
              ],
            ),
          ),
          const _Label('Volume'),
          Slider(
            key: const Key('alertVolume'),
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
                : (value) => setState(
                    () => _dragged = AlertSettings.clampVolume(value),
                  ),
            onChangeEnd: settings.sound == null
                ? null
                : (value) {
                    setState(() => _dragged = null);
                    _tell(
                      _controller.change(
                        settings.copyWith(
                          volume: AlertSettings.clampVolume(value),
                        ),
                      ),
                    );
                  },
          ),
          const _Label('Vibration'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<AlertVibration>(
              key: const Key('alertVibration'),
              showSelectedIcon: false,
              segments: [
                for (final v in AlertVibration.values)
                  ButtonSegment(value: v, label: Text(v.label)),
              ],
              selected: {settings.vibration},
              onSelectionChanged: (selected) => _tell(
                _controller.change(
                  settings.copyWith(vibration: selected.single),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
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
