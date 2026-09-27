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
    this.link,
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
    link: parseLink(json['link']),
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

  /// The URL the owner can open from the event; `null` when it has none, or
  /// one the app cannot open (see [parseLink]).
  final Uri? link;
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
    link: link,
    occurredAt: occurredAt,
    createdAt: createdAt,
    readAt: readAt,
  );
}

/// An event's `link` when it is what the server accepts: an absolute `http`
/// or `https` URL with a host. Anything else, including a missing field from
/// a server released before links, is no link rather than an error, so the
/// event is still shown and nothing but a web address is ever handed to the
/// platform to open.
Uri? parseLink(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
    return null;
  }
  return uri.host.isEmpty ? null : uri;
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
