import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/client_registration.dart';
import '../settings/settings_groups.dart';
import 'alert_section.dart';
import 'devices_screen.dart';
import 'push_filters.dart';

/// Every setting of the app, opened from the inbox's gear icon: the _Push
/// notifications_ switch, then folding groups that show a summary of their
/// values while folded, and on an admin device a row that opens the
/// owner's devices. Push preferences are saved on the server, the alert and
/// the open groups on the device; each change is saved at once.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Do Not Disturb access is given in the phone's settings, which the
    // owner comes back from.
    _lifecycle = AppLifecycleListener(
      onResume: () => _controller.alert?.refreshDoNotDisturbAccess(),
    );
    // For the Devices row's summary. Not while building: reading them
    // notifies the controller's listeners.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.loadDevices(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _controller.refresh();
    await _controller.loadDevices();
  }

  Future<void> _save(PushPreferences changed) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await _controller.setPushPreferences(changed);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListenableBuilder(
      // The alert's summaries follow its settings.
      listenable: Listenable.merge([_controller, ?_controller.alert]),
      builder: (context, _) {
        final preferences = _controller.registration?.pushPreferences;
        final alert = _controller.alert;
        // Pushes are paused: what shapes them is kept, and can be changed.
        final paused = preferences != null && !preferences.enabled;
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (preferences != null)
                PushSwitch(
                  preferences: preferences,
                  enabled: !_controller.savingPushPreferences,
                  save: _save,
                ),
              _group(
                SettingsGroup.pushFilters,
                title: 'Push filters',
                greyed: paused,
                summary: preferences == null
                    ? 'Not supported by this server'
                    : PushFilters.summary(
                        preferences,
                        _controller.inboxProducers,
                      ),
                child: preferences == null
                    ? const ListTile(
                        title: Text(
                          'This server does not support push preferences. '
                          'Update it to choose which events are pushed to '
                          'this device.',
                        ),
                      )
                    : PushFilters(
                        preferences: preferences,
                        enabled: !_controller.savingPushPreferences,
                        producers: _controller.inboxProducers,
                        save: _save,
                      ),
              ),
              if (alert != null) ...[
                _group(
                  SettingsGroup.alert,
                  title: 'Alert',
                  greyed: paused,
                  summary: GeneralAlertSection.summary(alert.settings),
                  child: GeneralAlertSection(controller: alert),
                ),
                _group(
                  SettingsGroup.critical,
                  title: 'Critical alert',
                  greyed: paused,
                  summary: CriticalAlertSection.summary(alert),
                  child: CriticalAlertSection(controller: alert),
                ),
              ],
              _group(
                SettingsGroup.device,
                title: 'This device',
                summary: [
                  _controller.registration?.name ?? 'This device',
                  _controller.pushStatus.description,
                ].join(' · '),
                child: _ThisDevice(controller: _controller),
              ),
              if (_controller.canManageDevices || _controller.lostAdminRights)
                ListTile(
                  key: const Key('devices'),
                  leading: const Icon(Icons.devices_outlined),
                  title: const Text('Devices'),
                  subtitle: switch (DevicesScreen.summary(_controller)) {
                    final summary? => Text(summary),
                    null => null,
                  },
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DevicesScreen(controller: _controller),
                    ),
                  ),
                ),
              // Clear of the navigation bar.
              SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
            ],
          ),
        );
      },
    ),
  );

  Widget _group(
    SettingsGroup group, {
    required String title,
    required String summary,
    required Widget child,
    bool greyed = false,
  }) => _Group(
    group: group,
    title: title,
    summary: summary,
    greyed: greyed,
    open: _controller.openSettingsGroups.contains(group),
    onOpened: (open) => _controller.setSettingsGroupOpen(group, open: open),
    child: child,
  );
}

/// A group of settings that folds, showing a one-line [summary] of its
/// values in its header. Greyed while the settings do not apply, and still
/// changeable.
class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.title,
    required this.summary,
    required this.greyed,
    required this.open,
    required this.onOpened,
    required this.child,
  });

  final SettingsGroup group;
  final String title;
  final String summary;
  final bool greyed;
  final bool open;
  final ValueChanged<bool> onOpened;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final grey = greyed ? Theme.of(context).disabledColor : null;
    return ExpansionTile(
      key: Key('group-${group.name}'),
      initiallyExpanded: open,
      onExpansionChanged: onOpened,
      textColor: grey,
      collapsedTextColor: grey,
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            summary,
            key: Key('summary-${group.name}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (greyed)
            Text(
              'Applies once push notifications are on',
              key: Key('pushOff-${group.name}'),
            ),
        ],
      ),
      children: [greyed ? Opacity(opacity: 0.5, child: child) : child],
    );
  }
}

/// This installation: its registration and server, push status and build,
/// and disconnecting it.
class _ThisDevice extends StatelessWidget {
  const _ThisDevice({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ListTile(
        leading: const Icon(Icons.phone_android),
        title: Text(controller.registration?.name ?? 'This device'),
        subtitle: switch (controller.credentials) {
          final credentials? => Text(credentials.baseUrl),
          null => null,
        },
      ),
      ListTile(
        leading: const Icon(Icons.notifications_outlined),
        title: Text(controller.pushStatus.description),
      ),
      ListTile(
        key: const Key('build'),
        leading: const Icon(Icons.info_outline),
        title: Text(controller.build.versionLine),
        subtitle: Text(controller.build.commitLine),
      ),
      ListTile(
        key: const Key('disconnect'),
        leading: const Icon(Icons.logout),
        title: const Text('Disconnect this device'),
        onTap: () => _disconnect(context),
      ),
    ],
  );

  Future<void> _disconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disconnect this device?'),
        content: const Text(
          'It gets no more pushes and forgets the server and its client '
          'key. To use it again, set it up again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    // Setup takes the inbox's place, under Settings.
    Navigator.of(context).popUntil((route) => route.isFirst);
    await controller.disconnect();
  }
}
