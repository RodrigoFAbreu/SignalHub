import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/client_registration.dart';
import 'connect_device_screen.dart';

/// This installation: its registration, server, push status and build. On
/// an admin device, also the owner's devices, to connect a new one, make one
/// an admin, revoke one that is not an admin or delete one that is revoked.
class DeviceScreen extends StatefulWidget {
  const DeviceScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // Not while building: reading them notifies the controller's listeners.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _controller.loadDevices(),
    );
  }

  Future<void> _refresh() async {
    await _controller.refresh();
    await _controller.loadDevices();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('This device')),
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          // Explicit padding drops the system insets a list pads by default:
          // without them, its end is hidden under the navigation bar.
          padding: const EdgeInsets.all(16) + MediaQuery.paddingOf(context),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text(_controller.registration?.name ?? 'This device'),
                subtitle: _controller.credentials == null
                    ? null
                    : Text(_controller.credentials!.baseUrl),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: Text(_controller.pushStatus.description),
              ),
            ),
            Card(
              child: ListTile(
                key: const Key('build'),
                leading: const Icon(Icons.info_outline),
                title: Text(_controller.build.versionLine),
                subtitle: Text(_controller.build.commitLine),
              ),
            ),
            if (_controller.lostAdminRights || _controller.canManageDevices)
              _DevicesSection(controller: _controller),
          ],
        ),
      ),
    ),
  );
}

/// The owner's devices, for an admin device. Actions are offered only where
/// the server accepts them: making an admin and revoking on devices that are
/// neither admins nor revoked, deleting on revoked devices.
class _DevicesSection extends StatelessWidget {
  const _DevicesSection({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = controller.devices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            'Devices',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
        ),
        if (controller.lostAdminRights)
          const Card(
            key: Key('notAdmin'),
            child: ListTile(
              leading: Icon(Icons.no_accounts_outlined),
              title: Text(AppController.notAdminMessage),
              subtitle: Text(
                'It can no longer manage devices. The operator, or another '
                'admin device, can make it one again.',
              ),
            ),
          )
        else if (devices != null) ...[
          if (controller.canCreatePairings)
            Card(
              child: ListTile(
                key: const Key('connectDevice'),
                leading: const Icon(Icons.qr_code_2),
                title: const Text('Connect a device'),
                subtitle: const Text('Pair a new device with a one-time code'),
                onTap: () => _connectDevice(context),
              ),
            ),
          for (final device in devices)
            _DeviceTile(
              device: device,
              isThisDevice: device.id == controller.registration?.id,
              busy: controller.changingDeviceId != null,
              makeAdmin: () => _makeAdmin(context, device),
              revoke: () => _revoke(context, device),
              delete: controller.canDeleteDevices
                  ? () => _delete(context, device)
                  : null,
            ),
        ] else if (controller.devicesError case final error?)
          Card(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(error),
              subtitle: const Text('Pull down to retry.'),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Future<void> _connectDevice(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ConnectDeviceScreen(controller: controller),
      ),
    );
    // The code is not kept once off screen, and the device it paired, if
    // any, is listed. Rights lost meanwhile stay explained instead.
    controller.clearPairing();
    if (controller.canManageDevices) await controller.loadDevices();
  }

  Future<void> _makeAdmin(BuildContext context, ManagedDevice device) async {
    final confirmed = await _confirm(
      context,
      title: 'Make "${device.name}" an admin device?',
      message:
          'It will be able to manage your devices, as this one does. Only '
          'the operator can take admin rights away, on the admin page.',
      action: 'Make an admin',
    );
    if (confirmed && context.mounted) {
      await _show(context, controller.makeDeviceAdmin(device.id));
    }
  }

  Future<void> _revoke(BuildContext context, ManagedDevice device) async {
    final confirmed = await _confirm(
      context,
      title: 'Revoke "${device.name}"?',
      message:
          'Its client key stops working at once and it gets no more pushes. '
          'This cannot be undone: to use it again, set it up again.',
      action: 'Revoke',
    );
    if (confirmed && context.mounted) {
      await _show(context, controller.revokeDevice(device.id));
    }
  }

  Future<void> _delete(BuildContext context, ManagedDevice device) async {
    final confirmed = await _confirm(
      context,
      title: 'Delete "${device.name}"?',
      message:
          'It leaves the list of devices for good. Events and whether they '
          'are read stay. This cannot be undone.',
      action: 'Delete',
    );
    if (confirmed && context.mounted) {
      await _show(context, controller.deleteDevice(device.id));
    }
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String action,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: const Key('confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  static Future<void> _show(
    BuildContext context,
    Future<String?> change,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await change;
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isThisDevice,
    required this.busy,
    required this.makeAdmin,
    required this.revoke,
    required this.delete,
  });

  final ManagedDevice device;
  final bool isThisDevice;
  final bool busy;
  final VoidCallback makeAdmin;
  final VoidCallback revoke;

  /// `null` when the server cannot delete devices.
  final VoidCallback? delete;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (isThisDevice) 'This device',
      if (device.admin) 'Admin device',
      if (device.isRevoked) 'Revoked',
    ];
    final delete = this.delete;
    final actions = <PopupMenuEntry<VoidCallback>>[
      if (!device.admin && !device.isRevoked) ...[
        PopupMenuItem(
          key: const Key('makeAdmin'),
          value: makeAdmin,
          child: const Text('Make an admin'),
        ),
        PopupMenuItem(
          key: const Key('revoke'),
          value: revoke,
          child: const Text('Revoke'),
        ),
      ],
      if (device.isRevoked && delete != null)
        PopupMenuItem(
          key: const Key('delete'),
          value: delete,
          child: const Text('Delete'),
        ),
    ];
    // Greyed out by hand: a disabled tile would also ignore its menu.
    final revokedColor = device.isRevoked
        ? Theme.of(context).disabledColor
        : null;
    return Card(
      key: Key('device-${device.id}'),
      child: ListTile(
        textColor: revokedColor,
        leading: Icon(
          device.admin
              ? Icons.admin_panel_settings_outlined
              : Icons.phone_android,
          color: revokedColor,
        ),
        title: Text(device.name),
        subtitle: details.isEmpty ? null : Text(details.join(' · ')),
        trailing: actions.isNotEmpty
            ? PopupMenuButton<VoidCallback>(
                key: Key('deviceActions-${device.id}'),
                tooltip: 'Manage',
                enabled: !busy,
                onSelected: (action) => action(),
                itemBuilder: (context) => actions,
              )
            : null,
      ),
    );
  }
}
