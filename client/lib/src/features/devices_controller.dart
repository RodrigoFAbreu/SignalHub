import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../models/client_registration.dart';
import '../models/users.dart';
import 'action_failure.dart';

/// The devices of one person, as the admin's Devices screen groups them.
class DeviceGroup {
  const DeviceGroup(this.user, this.devices);

  /// `null` for devices a server released before users lists.
  final UserRef? user;
  final List<ManagedDevice> devices;
}

/// The devices this role may list and manage (`/api/v1/client/devices`): an
/// admin's key gets everyone's, a mod's and a basic user's key their own.
/// Revoking, renaming and deleting go through here; what each role may do is
/// the server's rule, and the screen only offers what it will accept.
class DevicesController extends ChangeNotifier {
  /// [thisDeviceId] is this installation's own client ID, for the one device
  /// that is "This device" and has no Revoke. [now] is the clock.
  DevicesController(
    this.gateway, {
    this.thisDeviceId = _noDevice,
    this.now = DateTime.now,
  });

  static String? _noDevice() => null;

  final ApiGateway gateway;
  final String? Function() thisDeviceId;
  final DateTime Function() now;

  /// Every device this role lists, as last read.
  final Resource<List<ManagedDevice>> list = Resource();

  /// Whether the server has no device endpoints (released before them).
  bool unsupported = false;

  /// The device a change is being made to; `null` when none is.
  String? busyId;

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Reads the devices again; the older list stays if that fails.
  Future<void> load() async {
    list.loading = true;
    notifyListeners();
    final read = await list.load(
      () => gateway.call((api) => api.listDevices()),
    );
    unsupported = !read && list.error?.statusCode == 404;
    notifyListeners();
  }

  /// Forgets what was read, so another server or role starts clean.
  void clear() {
    list.clear();
    unsupported = false;
    busyId = null;
    notifyListeners();
  }

  List<ManagedDevice> get devices => list.value ?? const [];

  ManagedDevice? byId(String id) =>
      devices.where((d) => d.id == id).firstOrNull;

  bool isThisDevice(ManagedDevice device) => device.id == thisDeviceId();

  /// A mod's or a basic user's devices, which are all the server lists, in
  /// the order a screen shows them. Only this user's, so what an admin read
  /// before the role changed is not shown to a user who is no longer one.
  List<ManagedDevice> get ownDevices => _ordered([
    for (final d in devices)
      if (d.user == null || d.user!.id == gateway.userId) d,
  ]);

  /// The devices of one person in the order a screen shows them: this device
  /// first, then the active ones as the server lists them (oldest first),
  /// then the revoked ones.
  List<ManagedDevice> devicesOf(String userId) => _ordered([
    for (final d in devices)
      if (d.user?.id == userId) d,
  ]);

  List<ManagedDevice> _ordered(List<ManagedDevice> of) => [
    ...of.where((d) => isThisDevice(d)),
    ...of.where((d) => !isThisDevice(d) && !d.isRevoked),
    ...of.where((d) => !isThisDevice(d) && d.isRevoked),
  ];

  /// What an admin's screen shows: the devices by person, this person first,
  /// then admins, mods and basic users, each by name.
  List<DeviceGroup> get groups {
    final byUser = <String, List<ManagedDevice>>{};
    final withoutUser = <ManagedDevice>[];
    final users = <String, UserRef>{};
    for (final device in devices) {
      final user = device.user;
      if (user == null) {
        withoutUser.add(device);
        continue;
      }
      users[user.id] = user;
      (byUser[user.id] ??= []).add(device);
    }
    final me = gateway.userId;
    final ordered = users.values.toList()
      ..sort((a, b) {
        if (a.id == me || b.id == me) return a.id == me ? -1 : 1;
        final byRole = b.role.index.compareTo(a.role.index);
        return byRole != 0
            ? byRole
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return [
      for (final user in ordered) DeviceGroup(user, _ordered(byUser[user.id]!)),
      if (withoutUser.isNotEmpty) DeviceGroup(null, _ordered(withoutUser)),
    ];
  }

  /// One line for Settings' _Devices_ row: `4 devices · 1 browser`; the
  /// devices an admin counts are everyone's. `null` until they are read.
  String? get summary {
    final read = list.value;
    if (read == null) return null;
    final active = read.where((d) => !d.isRevoked);
    final browsers = active.where((d) => d.isBrowser).length;
    final count = active.length;
    if (count == 0) return 'No devices';
    return [
      _count(count, 'device'),
      if (browsers > 0) _count(browsers, 'browser'),
    ].join(' · ');
  }

  static String _count(int n, String noun) =>
      n == 1 ? '1 $noun' : '$n ${noun}s';

  /// Renames [device]. Returns why it did not work, or `null`.
  Future<ActionFailure?> rename(ManagedDevice device, String name) => _change(
    device,
    _Change.rename,
    'rename ${device.name}',
    (api) async => _replace(await api.renameDevice(device.id, name.trim())),
  );

  /// Revokes [device]: for good. Returns why it did not work, or `null`.
  Future<ActionFailure?> revoke(ManagedDevice device) => _change(
    device,
    _Change.revoke,
    '${device.isBrowser ? 'sign out' : 'revoke'} ${device.name}',
    (api) async => _replace(await api.revokeDevice(device.id)),
  );

  /// Deletes the revoked [device]. Returns why it did not work, or `null`.
  Future<ActionFailure?> delete(ManagedDevice device) =>
      _change(device, _Change.delete, 'delete ${device.name}', (api) async {
        await api.deleteDevice(device.id);
        list.value = devices.where((d) => d.id != device.id).toList();
      });

  void _replace(ManagedDevice changed) {
    list.value = [
      for (final d in devices)
        if (d.id == changed.id) d.after(changed) else d,
    ];
  }

  /// Shows [shown] as the devices read, for tests of what the server cannot
  /// say yet, such as a device that is a browser.
  @visibleForTesting
  void show(List<ManagedDevice> shown) {
    list.value = shown;
    list.error = null;
    notifyListeners();
  }

  Future<ActionFailure?> _change(
    ManagedDevice device,
    _Change change,
    String what,
    Future<void> Function(SignalHubApi api) apply,
  ) async {
    busyId = device.id;
    notifyListeners();
    final role = gateway.role;
    try {
      await gateway.call(apply);
      return null;
    } on SignedOutException {
      return const ActionFailure.quiet();
    } on ApiException catch (e) {
      return await _failure(device, change, what, e, role);
    } finally {
      busyId = null;
      notifyListeners();
    }
  }

  Future<ActionFailure?> _failure(
    ManagedDevice device,
    _Change change,
    String what,
    ApiException e,
    UserRole before,
  ) async {
    final status = e.statusCode;
    // The role was read again: if it changed, the screen already follows it
    // and the shell says so; otherwise this role may not.
    if (status == 403) return ActionFailure.refused(before, gateway.role);
    if (status == 405 && change == _Change.delete) return _cannotDelete();
    if (status != 404 && status != 409) return ActionFailure.generic(e, what);
    // Changed meanwhile, by the host or another admin's device: show it as
    // it is now, and say what that means for this change.
    await load();
    final fresh = byId(device.id);
    if (fresh == null) {
      if (status == 404 && change == _Change.delete) return null;
      return const ActionFailure(
        FailureKind.gone,
        'That device was already removed.',
      );
    }
    if (status == 404 && change == _Change.delete) return _cannotDelete();
    if (fresh.admin) {
      return const ActionFailure(FailureKind.adminDevice, adminDeviceMessage);
    }
    return switch (change) {
      _Change.revoke when fresh.isRevoked => null,
      _Change.revoke when gateway.role == UserRole.mod => const ActionFailure(
        FailureKind.lastActiveDevice,
        lastActiveMessage,
      ),
      _Change.rename when fresh.isRevoked => const ActionFailure(
        FailureKind.other,
        "That device is revoked, so its name can't change.",
      ),
      _Change.delete when fresh.isRevoked => null,
      _Change.delete => const ActionFailure(
        FailureKind.other,
        "That device isn't revoked, so it can't be deleted.",
      ),
      _ => ActionFailure.generic(e, what),
    };
  }

  ActionFailure _cannotDelete() => const ActionFailure(
    FailureKind.unsupported,
    'This server cannot delete devices. Update SignalHub, or delete it on the '
    'admin page.',
  );

  /// `409` on an admin's device, whoever asks.
  static const adminDeviceMessage =
      "That's an admin device. Admin devices are managed on the admin page.";

  /// A mod's last active device, which the server will not revoke.
  static const lastActiveMessage =
      "It's your last active device. Revoking it would lock you out. Connect "
      'another device first.';
}

enum _Change { rename, revoke, delete }

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `4 Oct`, or `4 Oct 2025` for another year than [now]'s, in local time.
String shortDate(DateTime when, DateTime now) {
  final local = when.toLocal();
  final year = local.year == now.year ? '' : ' ${local.year}';
  return '${local.day} ${_months[local.month - 1]}$year';
}

/// The second line of a device row: when it was revoked, that it is the
/// device in use, when it was last active, or that it has not been used.
/// [inUse] is the device this app runs on; a browser in use says when it was
/// last active, since its `This browser` tag says which it is.
String deviceActivity(
  ManagedDevice device,
  DateTime now, {
  bool inUse = false,
}) {
  final revokedAt = device.revokedAt;
  if (revokedAt != null) return 'Revoked ${shortDate(revokedAt, now)}';
  if (inUse && !device.isBrowser) return 'This device';
  final last = device.lastActiveAt;
  if (last == null) return 'Not used yet';
  final today = DateTime.utc(now.year, now.month, now.day);
  final local = last.toLocal();
  final day = DateTime.utc(local.year, local.month, local.day);
  final days = today.difference(day).inDays;
  return switch (days) {
    <= 0 => 'Last active today',
    1 => 'Last active yesterday',
    < 7 => 'Last active $days days ago',
    _ => 'Last active ${shortDate(last, now)}',
  };
}
