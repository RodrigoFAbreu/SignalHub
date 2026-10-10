import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/client_registration.dart';
import '../models/event.dart';
import '../settings/settings_groups.dart';
import 'about_server_screen.dart';
import 'alert_section.dart';
import 'devices_screen.dart';
import 'push_filters.dart';
import 'widgets/snack.dart';

/// Every setting of the app, a tab of the bottom bar: the _Push
/// notifications_ switch, then, in one order for every role, _Push filters_
/// and _Alert_ (folding groups that show a summary of their values while
/// folded), _Devices_ and _About this server_ (rows that open a screen) and
/// _This device_. Push preferences are saved on the server, the alert and the
/// open groups on the device; each change is saved at once.
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
    // For the Devices row's summary and the producers Push filters lists.
    // Not while building: reading them notifies the listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLists());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _loadLists() => Future.wait([
    _controller.deviceList.load(),
    _controller.producers.load(),
  ]);

  Future<void> _refresh() async {
    await _controller.refresh();
    await _loadLists();
  }

  Future<void> _save(PushPreferences changed) async {
    final error = await _controller.setPushPreferences(changed);
    if (error != null && mounted) showAppSnackBar(context, error);
  }

  /// The address of the server, as the app reaches it.
  String? get _host =>
      Uri.tryParse(_controller.credentials?.baseUrl ?? '')?.authority;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListenableBuilder(
      // The alert's summaries follow its settings.
      listenable: Listenable.merge([
        _controller,
        _controller.deviceList,
        _controller.producers,
        ?_controller.alert,
      ]),
      builder: (context, _) {
        final preferences = _controller.registration?.pushPreferences;
        final alert = _controller.alert;
        final producers = _controller.producers;
        // Names for the producers a muted ID may belong to: those this user
        // sees, or else the ones an event of the inbox came from.
        final names = {
          for (final id in preferences?.mutedProducerIds ?? const <String>[])
            id: ?_controller.producerName(id),
        };
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
                icon: Icons.notifications_outlined,
                greyed: paused,
                summary: preferences == null
                    ? 'Not supported by this server'
                    : PushFilters.summary(preferences, names),
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
                        producers: [
                          for (final p in producers.subscribed)
                            EventProducer(id: p.id, name: p.name),
                        ],
                        names: names,
                        save: _save,
                      ),
              ),
              if (alert != null)
                _group(
                  SettingsGroup.alert,
                  title: 'Alert',
                  icon: Icons.volume_up_outlined,
                  greyed: paused,
                  summary: GeneralAlertSection.summary(alert),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GeneralAlertSection(controller: alert),
                      // Critical events' own alert, usable only while they
                      // have one.
                      _group(
                        SettingsGroup.critical,
                        title: 'Critical alert',
                        icon: Icons.priority_high,
                        enabled: alert.critical.different,
                        summary: CriticalAlertSection.summary(alert),
                        child: CriticalAlertSection(controller: alert),
                      ),
                    ],
                  ),
                ),
              // Every role has the Devices screen: a Basic user's is read
              // only.
              ListTile(
                key: const Key('devices'),
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Devices'),
                subtitle: switch (_controller.deviceList.summary) {
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
              ListTile(
                key: const Key('aboutServer'),
                leading: Icon(
                  Icons.dns_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('About this server'),
                subtitle: Text(
                  [?_host, 'who can see what'].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AboutServerScreen(controller: _controller),
                  ),
                ),
              ),
              _group(
                SettingsGroup.device,
                title: 'This device',
                icon: Icons.phone_android,
                summary: [
                  _controller.registration?.name ?? 'This device',
                  _controller.pushStatus.description,
                ].join(' · '),
                child: _ThisDevice(controller: _controller),
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
    required IconData icon,
    required String summary,
    required Widget child,
    bool greyed = false,
    bool enabled = true,
  }) => _Group(
    group: group,
    title: title,
    icon: icon,
    summary: summary,
    greyed: greyed,
    enabled: enabled,
    open: _controller.openSettingsGroups.contains(group),
    onOpened: (open) => _controller.setSettingsGroupOpen(group, open: open),
    child: child,
  );
}

/// A group of settings that folds, showing a one-line [summary] of its
/// values in its header. Greyed while the settings do not apply, and still
/// changeable; or, not [enabled], greyed, folded and not to be opened, its
/// open state kept for when it is enabled again.
class _Group extends StatelessWidget {
  const _Group({
    required this.group,
    required this.title,
    required this.icon,
    required this.summary,
    required this.greyed,
    required this.enabled,
    required this.open,
    required this.onOpened,
    required this.child,
  });

  final SettingsGroup group;
  final String title;
  final IconData icon;
  final String summary;
  final bool greyed;
  final bool enabled;
  final bool open;
  final ValueChanged<bool> onOpened;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final grey = greyed || !enabled ? Theme.of(context).disabledColor : null;
    // A new tile once it is enabled or not, so it folds when disabled and
    // opens as it was left when enabled again.
    return KeyedSubtree(key: ValueKey(enabled), child: _tile(grey));
  }

  Widget _tile(Color? grey) => ExpansionTile(
    key: Key('group-${group.name}'),
    enabled: enabled,
    initiallyExpanded: enabled && open,
    onExpansionChanged: onOpened,
    textColor: grey,
    collapsedTextColor: grey,
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    leading: Icon(icon),
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
