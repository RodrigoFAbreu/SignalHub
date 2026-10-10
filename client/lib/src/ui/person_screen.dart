import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/action_failure.dart';
import '../features/devices_controller.dart';
import '../features/people_controller.dart';
import '../models/client_registration.dart';
import '../models/users.dart';
import 'connect_device_screen.dart';
import 'device_rows.dart';
import 'widgets/app_row.dart';
import 'widgets/callout.dart';
import 'widgets/empty_state.dart';
import 'widgets/role_gate.dart';
import 'widgets/skeleton.dart';
import 'widgets/snack.dart';
import 'widgets/dialogs.dart';
import 'widgets/tags.dart';

/// A person, as an admin sees them: their role (Basic or Mod, which an admin
/// sets; Admin is shown but set on the admin page), their devices, which an
/// admin revokes, and the producers they own. Another admin's page, and your
/// own, are read only: nothing on them is a control.
class PersonScreen extends StatelessWidget {
  const PersonScreen({
    super.key,
    required this.controller,
    required this.personId,
  });

  final AppController controller;
  final String personId;

  @override
  Widget build(BuildContext context) => RoleGate(
    controller: controller,
    allows: (role) => role.isAdmin,
    child: _Person(controller: controller, personId: personId),
  );
}

class _Person extends StatefulWidget {
  const _Person({required this.controller, required this.personId});

  final AppController controller;
  final String personId;

  @override
  State<_Person> createState() => _PersonState();
}

class _PersonState extends State<_Person> {
  AppController get _app => widget.controller;
  PeopleController get _people => _app.people;
  DevicesController get _devices => _app.deviceList;
  String get _id => widget.personId;
  late final DeviceActions _actions = DeviceActions(context, _app);

  /// The person as last listed: kept when a later list no longer has them,
  /// so the page they were on does not change under a message.
  Person? _person;

  /// Whether opening the page found the person removed.
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _person = _people.byId(_id);
    // Not while building: reading notifies the controller's listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    await Future.wait([
      _people.loadProducers(_id),
      _devices.load(),
      _people.load(),
    ]);
    if (mounted && _people.wasRemoved(_id)) setState(() => _gone = true);
  }

  Future<void> _changeRole(Person person, UserRole role) async {
    if (role == person.role) return;
    final name = person.name;
    final basic = role == UserRole.basic;
    final confirmed = await showConfirmDialog(
      context,
      title: basic ? 'Make $name a Basic user?' : 'Make $name a Mod?',
      message: basic
          ? '$name will no longer be able to connect, rename or revoke '
                'devices. Their producers and subscriptions stay. It applies '
                'on their next action.'
          : '$name will be able to connect, rename, revoke and delete their '
                'own devices.',
      action: basic ? 'Make Basic' : 'Make Mod',
    );
    if (confirmed && mounted) await _apply(person, role);
  }

  Future<void> _apply(Person person, UserRole role) async {
    final failure = await _people.setRole(person, role);
    if (failure == null || failure.isQuiet || !mounted) return;
    showAppSnackBar(
      context,
      failure.message,
      actionLabel: failure.canRetry ? 'Retry' : null,
      onAction: failure.canRetry ? () => _apply(person, role) : null,
    );
  }

  Future<void> _pair(Person person) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectDeviceScreen(
          controller: _app,
          forPerson: (id: person.id, name: person.name),
        ),
      ),
    );
    if (mounted) unawaited(_devices.load());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_app, _people, _devices]),
    builder: (context, _) {
      _person = _people.byId(_id) ?? _person;
      final person = _person;
      final you = _id == _app.userId;
      return Scaffold(
        appBar: AppBar(
          // The drawings start the title where the back arrow ends.
          titleSpacing: 0,
          title: Row(
            children: [
              Flexible(
                child: Text(
                  person?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (you) ...[
                const SizedBox(width: 8),
                const LabelTag('You', style: LabelTagStyle.primary),
              ],
            ],
          ),
        ),
        body: _gone
            ? EmptyState(
                icon: Icons.person_off,
                title: 'This person was removed',
                body:
                    'They no longer have access to this server, so there is '
                    'nothing to change.',
                actionLabel: 'Back to People',
                onAction: () => Navigator.of(context).pop(),
              )
            : person == null
            ? const SkeletonRows(count: 3)
            : _page(context, person, you: you),
      );
    },
  );

  Widget _page(BuildContext context, Person person, {required bool you}) {
    final theme = Theme.of(context);
    final isAdmin = person.role == UserRole.admin;
    // Nothing is a control on an admin's page, or on your own.
    final readOnly = isAdmin || you;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          const SectionLabel('Role'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _roleControl(person, readOnly: readOnly),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              readOnly
                  ? 'Admins are managed on the admin page, on the computer '
                        'running SignalHub.'
                  : 'Admin is set on the admin page, on the computer running '
                        'SignalHub.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SectionLabel('Devices'),
          ..._deviceRows(person, readOnly: readOnly),
          const SectionLabel('Producers'),
          ..._producerRows(person),
        ],
      ),
    );
  }

  Widget _roleControl(Person person, {required bool readOnly}) {
    final role = person.role ?? UserRole.basic;
    return SegmentedButton<UserRole>(
      key: const Key('role'),
      segments: [
        ButtonSegment(value: UserRole.basic, label: const Text('Basic')),
        ButtonSegment(value: UserRole.mod, label: const Text('Mod')),
        ButtonSegment(
          value: UserRole.admin,
          enabled: false,
          // Said in words: a disabled segment alone does not say why.
          label: role == UserRole.admin
              ? const Text('Admin')
              : Semantics(
                  label: 'Admin, not available. Set on the admin page',
                  excludeSemantics: true,
                  child: const Text('Admin'),
                ),
        ),
      ],
      selected: {role},
      onSelectionChanged: readOnly
          ? null
          : (chosen) => _changeRole(person, chosen.single),
    );
  }

  List<Widget> _deviceRows(Person person, {required bool readOnly}) {
    final list = _devices.list;
    if (list.showSkeleton) {
      return const [SkeletonRows(count: 2, circleLeading: false)];
    }
    final devices = _devices.devicesOf(person.id);
    return [
      for (final device in devices)
        DeviceRow(
          key: Key('device-${device.id}'),
          device: device,
          now: _devices.now(),
          inUse: _devices.isThisDevice(device),
          trailing: _deviceButton(device),
        ),
      if (list.failedWithoutList)
        _InlineFailure("Couldn't load devices.", _devices.load),
      if (readOnly)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Callout(
            kind: CalloutKind.neutral,
            icon: Icons.info_outline,
            child: Text(
              "An admin's devices can't be renamed or revoked from the app.",
            ),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('pairForPerson'),
              onPressed: () => _pair(person),
              icon: const Icon(Icons.add, size: 18),
              label: Text('Pair a device for ${person.name}'),
            ),
          ),
        ),
    ];
  }

  Widget? _deviceButton(ManagedDevice device) {
    if (device.admin) return null;
    final busy = _devices.busyId == device.id;
    if (device.isRevoked) {
      return DeviceButton(
        label: 'Delete',
        device: device,
        destructive: true,
        onPressed: busy ? null : () => _actions.delete(device),
      );
    }
    return DeviceButton(
      label: device.isBrowser ? 'Sign out' : 'Revoke',
      device: device,
      onPressed: busy ? null : () => _actions.revoke(device),
    );
  }

  List<Widget> _producerRows(Person person) {
    final producers = _people.producersOf(person.id);
    if (producers.showSkeleton) {
      return const [SkeletonRows(count: 2, circleLeading: false)];
    }
    if (producers.failedWithoutList) {
      return [
        _InlineFailure(
          "Couldn't load ${possessive(person.name)} producers.",
          () => _people.loadProducers(person.id),
        ),
      ];
    }
    final list = producers.value ?? const <PersonProducer>[];
    if (list.isEmpty) {
      final theme = Theme.of(context);
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Text(
            '${person.name} has no producers.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ];
    }
    return [
      for (final p in list)
        AppRow(
          key: Key('producer-${p.id}'),
          leading: Icon(
            Icons.sensors,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          title: p.name,
          subtitle: p.disabled
              ? '${p.visibility.label} · Disabled'
              : p.visibility.label,
        ),
    ];
  }
}

class _InlineFailure extends StatelessWidget {
  const _InlineFailure(this.message, this.onRetry);

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Try again')),
      ],
    ),
  );
}
