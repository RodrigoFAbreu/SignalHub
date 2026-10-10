import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/devices_controller.dart';
import '../models/client_registration.dart';
import '../models/users.dart';
import 'connect_device_screen.dart';
import 'device_rows.dart';
import 'widgets/app_row.dart';
import 'widgets/callout.dart';
import 'widgets/empty_state.dart';
import 'widgets/resource_status.dart';
import 'widgets/role_gate.dart';
import 'widgets/skeleton.dart';
import 'widgets/tags.dart';

/// The devices of every role, opened from Settings or a device notice. What
/// it shows and offers follows the role the server last said:
///
/// - a basic user sees their own, read only, with who can help;
/// - a mod sees their own, connects new ones and renames and revokes them
///   from the row menu;
/// - an admin sees everyone's, grouped by person, can also delete revoked
///   ones, and connects a device for anyone. An admin's own devices cannot be
///   changed from a device.
///
/// A role that changes while the screen is open rebuilds it; the shell says
/// so once.
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => RoleGate(
    controller: controller,
    allows: (_) => true,
    child: _Devices(controller: controller),
  );
}

class _Devices extends StatefulWidget {
  const _Devices({required this.controller});

  final AppController controller;

  @override
  State<_Devices> createState() => _DevicesState();
}

class _DevicesState extends State<_Devices> {
  AppController get _app => widget.controller;
  DevicesController get _devices => _app.deviceList;
  late final DeviceActions _actions = DeviceActions(context, _app);

  late UserRole _role = _app.role;

  @override
  void initState() {
    super.initState();
    _app.addListener(_followRole);
    // Not while building: reading notifies the controller's listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) => _devices.load());
  }

  @override
  void dispose() {
    _app.removeListener(_followRole);
    super.dispose();
  }

  /// A role that changed lists other devices: read them again.
  void _followRole() {
    if (_app.role == _role) return;
    _role = _app.role;
    unawaited(_devices.load());
  }

  Future<void> _refresh() async {
    // The role may have changed: read it again with the devices.
    await _app.rereadRegistration();
    await _devices.load();
  }

  Future<void> _connect() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectDeviceScreen(controller: _app),
      ),
    );
    // The device it paired, if any, is listed.
    if (mounted) unawaited(_devices.load());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Devices'), titleSpacing: 0),
    body: ListenableBuilder(
      listenable: Listenable.merge([_app, _devices]),
      builder: (context, _) => _body(context),
    ),
  );

  Widget _body(BuildContext context) {
    final list = _devices.list;
    if (_devices.unsupported) {
      return const EmptyState(
        icon: Icons.devices_other,
        title: "This server can't manage devices",
        body:
            'Update SignalHub on the server, or manage devices on the admin '
            'page.',
      );
    }
    if (list.showSkeleton) {
      return const SkeletonRows(count: 4, circleLeading: false);
    }
    if (list.failedWithoutList) {
      return LoadFailed(
        resource: list,
        what: 'devices',
        onRetry: _devices.load,
      );
    }
    final role = _app.role;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (list.stale) StaleBanner(resource: list, onRetry: _devices.load),
          if (role.managesDevices) _connectRow(role),
          if (role.isAdmin)
            for (final group in _devices.groups) ..._group(group, role)
          else ...[
            if (role == UserRole.mod) const SectionLabel('Yours'),
            for (final device in _devices.ownDevices) _row(device, role),
          ],
          if (!role.managesDevices)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Callout(
                kind: CalloutKind.neutral,
                icon: Icons.info_outline,
                child: Text(
                  'To add or remove a device, ask an admin of this server.',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _connectRow(UserRole role) => AppRow(
    key: const Key('connectDevice'),
    leading: Icon(
      Icons.add_circle_outline,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: 'Connect a device',
    subtitle: role.isAdmin
        ? 'For you or for someone else'
        : 'Pair a new device with a one-time code',
    onTap: _connect,
  );

  List<Widget> _group(DeviceGroup group, UserRole role) {
    final user = group.user;
    return [
      SectionLabel(
        user?.name ?? 'Devices',
        trailing: user == null ? null : RoleTag(user.role),
      ),
      for (final device in group.devices) _row(device, role),
    ];
  }

  Widget _row(ManagedDevice device, UserRole role) {
    final inUse = _devices.isThisDevice(device);
    return DeviceRow(
      key: Key('device-${device.id}'),
      device: device,
      now: _devices.now(),
      inUse: inUse,
      trailing: _trailing(device, role, inUse: inUse),
    );
  }

  /// Whether the device is this user's own.
  bool _isOwn(ManagedDevice device) =>
      device.user == null || device.user!.id == _app.userId;

  /// The one control a row offers this role, if any. Nothing is a disabled
  /// button: what a role cannot do is not drawn.
  Widget? _trailing(
    ManagedDevice device,
    UserRole role, {
    required bool inUse,
  }) {
    final busy = _devices.busyId == device.id;
    // Every role signs out, renames and deletes its own browsers, an admin
    // included; the server refuses nothing else to a basic user.
    final ownBrowser = device.isBrowser && _isOwn(device);
    if (device.isRevoked) {
      // A revoked device never changes again; only deleting it is left.
      return role.managesDevices || ownBrowser
          ? DeviceButton(
              label: 'Delete',
              device: device,
              destructive: true,
              onPressed: busy ? null : () => _actions.delete(device),
            )
          : null;
    }
    // No device changes an admin's device, its own included, but for the
    // browsers its user signed in.
    if (device.admin && !ownBrowser) return null;
    if (role.managesDevices) {
      return DeviceMenu(
        key: Key('menu-${device.id}'),
        device: device,
        actions: _actions,
        canRevoke: !inUse,
        busy: busy,
      );
    }
    // A basic user signs out their own browsers, and nothing else.
    if (ownBrowser && !inUse) {
      return DeviceButton(
        label: 'Sign out',
        device: device,
        onPressed: busy ? null : () => _actions.revoke(device),
      );
    }
    return null;
  }
}
