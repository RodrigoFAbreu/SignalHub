import 'package:flutter/foundation.dart';

import 'event.dart';

/// Which events the inbox shows. The server applies it through the
/// listing's filters (`read`, `producerId`, `category`, `severity`): values
/// within one set are alternatives, and everything chosen must match. Empty
/// sets mean no restriction.
@immutable
class InboxFilter {
  const InboxFilter({
    this.unreadOnly = false,
    this.producerIds = const {},
    this.categories = const {},
    this.severities = const {},
  });

  /// Every event.
  static const none = InboxFilter();

  /// Only events not read yet.
  final bool unreadOnly;
  final Set<String> producerIds;
  final Set<EventCategory> categories;
  final Set<EventSeverity> severities;

  bool get isActive => unreadOnly || narrowsEvents;

  /// Whether it leaves out events by what they are, not by whether they are
  /// read. Marking read up to an event would then mark events the owner
  /// cannot see.
  bool get narrowsEvents =>
      producerIds.isNotEmpty || categories.isNotEmpty || severities.isNotEmpty;

  /// Whether the inbox shows [event] when a page brings it. A server released
  /// before the `read` filter ignores it and returns read events too.
  bool admits(Event event) => !unreadOnly || !event.isRead;

  InboxFilter copyWith({
    bool? unreadOnly,
    Set<String>? producerIds,
    Set<EventCategory>? categories,
    Set<EventSeverity>? severities,
  }) => InboxFilter(
    unreadOnly: unreadOnly ?? this.unreadOnly,
    producerIds: producerIds ?? this.producerIds,
    categories: categories ?? this.categories,
    severities: severities ?? this.severities,
  );

  /// The listing's query parameters for this filter.
  Map<String, List<String>> get queryParameters => {
    if (unreadOnly) 'read': ['false'],
    if (producerIds.isNotEmpty) 'producerId': [...producerIds]..sort(),
    if (categories.isNotEmpty)
      'category': [for (final c in categories) c.wireName]..sort(),
    if (severities.isNotEmpty)
      'severity': [for (final s in severities) s.wireName]..sort(),
  };

  @override
  bool operator ==(Object other) =>
      other is InboxFilter &&
      other.unreadOnly == unreadOnly &&
      setEquals(other.producerIds, producerIds) &&
      setEquals(other.categories, categories) &&
      setEquals(other.severities, severities);

  @override
  int get hashCode => Object.hash(
    unreadOnly,
    Object.hashAllUnordered(producerIds),
    Object.hashAllUnordered(categories),
    Object.hashAllUnordered(severities),
  );
}

/// Adds [value] to [set] if it is not in it, and removes it if it is.
Set<T> toggled<T>(Set<T> set, T value) =>
    set.contains(value) ? ({...set}..remove(value)) : {...set, value};
