import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/action_failure.dart';
import '../features/devices_controller.dart';
import '../models/client_registration.dart';
import 'connect_device_screen.dart';
import 'widgets/app_row.dart';
import 'widgets/dialogs.dart';
import 'widgets/name_field.dart';
import 'widgets/snack.dart';
import 'widgets/tags.dart';

/// A device as the lists show it: an icon (a globe for a browser), its name
/// with the tags that apply (`Admin device`, `Browser`, `This browser`,
/// `Revoked`) and one line on when it was last active, when it was revoked
/// or that it is the device in use or has not been used. A revoked device is
/// greyed. What can be done with it is the [trailing] control.
class DeviceRow extends StatelessWidget {
  const DeviceRow({
    super.key,
    required this.device,
    required this.now,
    this.inUse = false,
    this.trailing,
  });

  final ManagedDevice device;
  final DateTime now;

  /// Whether it is the device this app runs on.
  final bool inUse;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AppRow(
    leading: Icon(
      device.isBrowser ? Icons.language : Icons.smartphone,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    title: device.name,
    tags: [
      if (device.admin && !device.isRevoked)
        const LabelTag('Admin device', style: LabelTagStyle.primary),
      if (device.isBrowser && inUse && !device.isRevoked)
        const LabelTag('This browser', style: LabelTagStyle.primary)
      else if (device.isBrowser)
        const LabelTag('Browser'),
      if (device.isRevoked) const LabelTag('Revoked'),
    ],
    subtitle: deviceActivity(device, now, inUse: inUse),
    trailing: trailing,
    trailingIsAction: trailing != null,
    greyed: device.isRevoked,
  );
}

/// What a person can do with one device from the app.
enum DeviceAction { rename, revoke }

/// The dialogs and messages of changing a device, shared by the Devices
/// screen and a person's page. A refusal is said in words; a failure that
/// trying again may fix comes with Retry.
class DeviceActions {
  const DeviceActions(this.context, this.app);

  final BuildContext context;
  final AppController app;

  DevicesController get _devices => app.deviceList;

  /// Whose device it is, for the dialogs: you, or their name.
  ({String name, bool you}) _owner(ManagedDevice device) {
    final user = device.user;
    if (user == null || user.id == app.userId) {
      return (name: app.userName ?? 'you', you: true);
    }
    return (name: user.name, you: false);
  }

  Future<void> rename(ManagedDevice device) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(current: device.name),
    );
    if (name == null || name == device.name || !context.mounted) return;
    await _run(() => _devices.rename(device, name));
  }

  Future<void> revoke(ManagedDevice device) async {
    final owner = _owner(device);
    final browser = device.isBrowser;
    final confirmed = await showConfirmDialog(
      context,
      title: browser ? 'Sign out ${device.name}?' : 'Revoke ${device.name}?',
      message: browser
          ? (owner.you
                ? 'This browser stops being a device of yours. To sign in '
                      'again, scan a new code from this app.'
                : 'This browser stops being a device of '
                      '${possessive(owner.name)}. ${owner.name} can sign in '
                      'again from their phone.')
          : (owner.you
                ? "It stops getting events at once and can't be used again. "
                      'To use it again, you have to connect it with a new '
                      'code. Your other devices and the admins are told.'
                : "It stops getting events at once and can't be used again. "
                      'To use it again, ${owner.name} has to connect it with '
                      'a new code. ${possessive(owner.name)} other devices '
                      'and the admins are told.'),
      action: browser ? 'Sign out' : 'Revoke',
      // Signing out can be undone by signing in again.
      destructive: !browser,
    );
    if (confirmed && context.mounted) await _run(() => _devices.revoke(device));
  }

  Future<void> delete(ManagedDevice device) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${device.name}?',
      message:
          'It is removed from the list with its push history. Events stay. '
          "This can't be undone, and nobody is notified.",
      action: 'Delete',
      destructive: true,
    );
    if (confirmed && context.mounted) await _run(() => _devices.delete(device));
  }

  Future<void> _run(Future<ActionFailure?> Function() change) async {
    final failure = await change();
    if (failure == null || failure.isQuiet || !context.mounted) return;
    if (failure.kind == FailureKind.lastActiveDevice) {
      await _lastActive();
      return;
    }
    showAppSnackBar(
      context,
      failure.message,
      actionLabel: failure.canRetry ? 'Retry' : null,
      onAction: failure.canRetry ? () => _run(change) : null,
    );
  }

  Future<void> _lastActive() async {
    final connect = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Can't revoke this device"),
        content: const SingleChildScrollView(
          child: Text(DevicesController.lastActiveMessage),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            key: const Key('connectInstead'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Connect a device'),
          ),
        ],
      ),
    );
    if (connect == true && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConnectDeviceScreen(controller: app),
        ),
      );
      if (context.mounted) await _devices.load();
    }
  }
}

/// A device's row menu: Rename and Revoke (Sign out for a browser), named
/// `More actions for NAME`. The device in use has no Revoke.
class DeviceMenu extends StatelessWidget {
  const DeviceMenu({
    super.key,
    required this.device,
    required this.actions,
    required this.canRevoke,
    required this.busy,
  });

  final ManagedDevice device;
  final DeviceActions actions;
  final bool canRevoke;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopupMenuButton<DeviceAction>(
      tooltip: 'More actions for ${device.name}',
      enabled: !busy,
      onSelected: (action) => switch (action) {
        DeviceAction.rename => actions.rename(device),
        DeviceAction.revoke => actions.revoke(device),
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: DeviceAction.rename,
          child: Row(
            children: [
              Icon(Icons.edit_outlined),
              SizedBox(width: 12),
              Text('Rename'),
            ],
          ),
        ),
        if (canRevoke)
          PopupMenuItem(
            value: DeviceAction.revoke,
            child: Row(
              children: [
                Icon(
                  device.isBrowser ? Icons.logout : Icons.block,
                  color: device.isBrowser ? null : colors.error,
                ),
                const SizedBox(width: 12),
                Text(
                  device.isBrowser ? 'Sign out' : 'Revoke',
                  style: TextStyle(
                    color: device.isBrowser ? null : colors.error,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A text button on a device row, named for the device: `Delete NAME`,
/// `Revoke NAME`, `Sign out NAME`.
class DeviceButton extends StatelessWidget {
  const DeviceButton({
    super.key,
    required this.label,
    required this.device,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final ManagedDevice device;
  final VoidCallback? onPressed;

  /// Whether it is drawn in the error colour: deleting, never revoking on a
  /// person's page, which the drawing keeps primary until it is confirmed.
  final bool destructive;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label ${device.name}',
    button: true,
    excludeSemantics: true,
    enabled: onPressed != null,
    onTap: onPressed,
    child: TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: destructive
            ? Theme.of(context).colorScheme.error
            : null,
      ),
      onPressed: onPressed,
      child: Text(label),
    ),
  );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.current);
  bool _touched = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty;

  void _save() {
    if (_valid) Navigator.of(context).pop(_name.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Rename device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            NameField(
              key: const Key('deviceName'),
              controller: _name,
              label: 'Device name',
              autofocus: true,
              errorText: _touched && !_valid ? 'Enter a name.' : null,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _touched = true),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            Text(
              '1 to 100 characters. The device keeps working. Nobody is '
              'notified.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('saveName'),
          onPressed: _valid ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
