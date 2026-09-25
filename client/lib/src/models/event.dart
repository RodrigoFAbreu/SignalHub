import 'json.dart';

/// What an event means for the owner. See docs/architecture.md, "Category and
/// severity".
///
/// The backend may add values in a later release, so an unrecognised value
/// maps to [unknown] instead of failing: the event is still shown.
enum EventCategory {
  actionRequired('ACTION_REQUIRED', 'Action required'),
  blocked('BLOCKED', 'Blocked'),
  completed('COMPLETED', 'Completed'),
  info('INFO', 'Info'),
  unknown('', 'Other');

  const EventCategory(this.wireName, this.label);

  final String wireName;
  final String label;

  static EventCategory parse(String value) => values.firstWhere(
    (c) => c != unknown && c.wireName == value,
    orElse: () => unknown,
  );
}

/// How urgently the owner should notice an event. Unrecognised values map to
/// [unknown], as for [EventCategory].
enum EventSeverity {
  low('LOW', 'Low'),
  normal('NORMAL', 'Normal'),
  high('HIGH', 'High'),
  critical('CRITICAL', 'Critical'),
  unknown('', 'Unknown');

  const EventSeverity(this.wireName, this.label);

  final String wireName;
  final String label;

  static EventSeverity parse(String value) => values.firstWhere(
    (s) => s != unknown && s.wireName == value,
    orElse: () => unknown,
  );
}

/// The producer that published an event.
class EventProducer {
  const EventProducer({required this.id, required this.name});

  factory EventProducer.fromJson(Map<String, Object?> json) =>
      EventProducer(id: json.string('id'), name: json.string('name'));

  final String id;
  final String name;
}

/// An event as the backend returns it (`GET /api/v1/events`).
class Event {
  const Event({
    required this.id,
    required this.producer,
    required this.category,
    required this.severity,
    required this.title,
    required this.createdAt,
    this.context,
    this.message,
    this.metadata = const {},
    this.occurredAt,
    this.readAt,
  });

  factory Event.fromJson(Map<String, Object?> json) => Event(
    id: json.string('id'),
    producer: EventProducer.fromJson(json.object('producer')),
    context: json.optionalString('context'),
    category: EventCategory.parse(json.string('category')),
    severity: EventSeverity.parse(json.string('severity')),
    title: json.string('title'),
    message: json.optionalString('message'),
    metadata: json.optionalObject('metadata') ?? const {},
    occurredAt: json.optionalTimestamp('occurredAt'),
    createdAt: json.timestamp('createdAt'),
    readAt: json.optionalTimestamp('readAt'),
  );

  final String id;
  final EventProducer producer;
  final String? context;
  final EventCategory category;
  final EventSeverity severity;
  final String title;
  final String? message;

  /// Opaque producer data. Shown, never interpreted.
  final Map<String, Object?> metadata;
  final DateTime? occurredAt;
  final DateTime createdAt;

  /// When the owner first read it, on any client; `null` while unread.
  final DateTime? readAt;

  bool get isRead => readAt != null;

  /// This event with its read state changed locally, for example after
  /// marking a range read on the server.
  Event withReadAt(DateTime? readAt) => Event(
    id: id,
    producer: producer,
    context: context,
    category: category,
    severity: severity,
    title: title,
    message: message,
    metadata: metadata,
    occurredAt: occurredAt,
    createdAt: createdAt,
    readAt: readAt,
  );
}

/// One page of the event listing.
class EventPage {
  const EventPage({required this.items, this.nextCursor});

  factory EventPage.fromJson(Map<String, Object?> json) => EventPage(
    items: json
        .list('items')
        .map((item) => Event.fromJson(asObject(item, 'items[]')))
        .toList(growable: false),
    nextCursor: json.optionalString('nextCursor'),
  );

  final List<Event> items;
  final String? nextCursor;
}
