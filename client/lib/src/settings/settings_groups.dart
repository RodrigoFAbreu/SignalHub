import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The folding groups of the Settings screen, in the order it shows them.
/// Their names are what [OpenGroupsStore] keeps.
enum SettingsGroup { pushFilters, alert, critical, device }

/// Keeps which groups of the Settings screen the owner left open, on the
/// device, across restarts and whichever server it connects to.
abstract interface class OpenGroupsStore {
  Future<Set<SettingsGroup>> load();

  Future<void> save(Set<SettingsGroup> open);
}

/// Stores the open groups in the platform's secure storage, the one store
/// the app already keeps on the device; nothing in them is secret.
class SecureOpenGroupsStore implements OpenGroupsStore {
  SecureOpenGroupsStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'signalhub.settings.openGroups';

  final FlutterSecureStorage _storage;

  @override
  Future<Set<SettingsGroup>> load() async {
    final names = (await _storage.read(key: _key))?.split(',') ?? const [];
    // A name a later version stored and this one lacks is ignored.
    return {
      for (final group in SettingsGroup.values)
        if (names.contains(group.name)) group,
    };
  }

  @override
  Future<void> save(Set<SettingsGroup> open) =>
      _storage.write(key: _key, value: open.map((g) => g.name).join(','));
}
