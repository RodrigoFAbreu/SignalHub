/// Typed reads from decoded JSON objects.
///
/// A response that does not match the documented contract fails with a
/// [FormatException] naming the field, rather than a cast error deep in the
/// UI.
extension JsonObject on Map<String, Object?> {
  String string(String key) => _required<String>(key);

  String? optionalString(String key) => _optional<String>(key);

  Map<String, Object?> object(String key) => asObject(this[key], key);

  Map<String, Object?>? optionalObject(String key) =>
      this[key] == null ? null : object(key);

  List<Object?> list(String key) => _required<List<Object?>>(key);

  DateTime timestamp(String key) => _parseTimestamp(key, string(key));

  DateTime? optionalTimestamp(String key) {
    final value = optionalString(key);
    return value == null ? null : _parseTimestamp(key, value);
  }

  T _required<T>(String key) {
    final value = this[key];
    if (value is T) return value;
    throw FormatException('Expected "$key" to be a $T, got $value');
  }

  T? _optional<T>(String key) => this[key] == null ? null : _required<T>(key);

  DateTime _parseTimestamp(String key, String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw FormatException('Expected "$key" to be a timestamp, got $value');
    }
    return parsed;
  }
}

Map<String, Object?> asObject(Object? value, String name) {
  if (value is Map<String, Object?>) return value;
  throw FormatException('Expected "$name" to be an object, got $value');
}
