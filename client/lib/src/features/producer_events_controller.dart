import 'package:flutter/foundation.dart';

import '../api/signalhub_api.dart';
import '../api_gateway.dart';
import '../models/event.dart';
import '../models/inbox_filter.dart';

/// The events of one producer, newest first, read page by page from
/// `GET /api/v1/events?producerId=`: the inbox narrowed to a producer. It has
/// its own list and filters, so it never touches the Inbox tab's.
///
/// Unread only, categories and severities combine with the producer; the
/// producer itself is not the screen's to remove from the filter (leaving it
/// leaves the screen).
class ProducerEventsController extends ChangeNotifier {
  ProducerEventsController({
    required this.gateway,
    required this.producerId,
    this.pageSize = 30,
  });

  final ApiGateway gateway;
  final String producerId;
  final int pageSize;

  List<Event> events = const [];

  /// Unread only, categories and severities, as chosen; [filter] adds the
  /// producer.
  InboxFilter extras = InboxFilter.none;

  /// Whether the first page has been read.
  bool loaded = false;

  /// Why the first page could not be read; `null` if it could.
  ApiException? error;

  bool loadingMore = false;
  String? loadMoreError;

  /// Whether every unread event is being marked read.
  bool markingAll = false;

  String? _cursor;
  Event? _lastRead;
  int _generation = 0;
  bool _disposed = false;

  /// What the listing is asked for.
  InboxFilter get filter => extras.copyWith(producerIds: {producerId});

  bool get hasMore => _cursor != null;

  /// Whether any filter besides the producer is on.
  bool get narrowed => extras.isActive;

  /// Whether an event shown is unread.
  bool get hasUnread => events.any((e) => !e.isRead);

  /// Reads the newest page; the events shown stay until it answers.
  Future<void> load() async {
    final generation = ++_generation;
    final asked = filter;
    try {
      final page = await gateway.call(
        (api) => api.listEvents(limit: pageSize, filter: asked),
      );
      if (generation != _generation) return;
      events = page.items.where(asked.admits).toList(growable: false);
      _cursor = page.nextCursor;
      _lastRead = page.items.lastOrNull;
      loaded = true;
      error = null;
      loadMoreError = null;
    } on SignedOutException {
      return;
    } on ApiException catch (e) {
      if (generation == _generation) error = e;
    }
    _notify();
  }

  /// Reads the next older page, if there is one.
  Future<void> loadMore() async {
    final cursor = _cursor;
    if (cursor == null || loadingMore) return;
    final generation = _generation;
    final asked = filter;
    loadingMore = true;
    loadMoreError = null;
    _notify();
    try {
      final page = await gateway.call(
        (api) => api.listEvents(limit: pageSize, cursor: cursor, filter: asked),
      );
      if (generation == _generation) {
        events = [...events, ...page.items.where(asked.admits)];
        _cursor = page.nextCursor;
        _lastRead = page.items.lastOrNull ?? _lastRead;
      }
    } on SignedOutException {
      loadingMore = false;
      return;
    } on ApiException catch (e) {
      if (generation == _generation) loadMoreError = e.message;
    }
    loadingMore = false;
    _notify();
  }

  /// Changes what is shown besides the producer, and reads again.
  Future<void> setExtras(InboxFilter next) async {
    final narrowed = next.copyWith(producerIds: const {});
    if (narrowed == extras) return;
    extras = narrowed;
    events = const [];
    _cursor = null;
    _lastRead = null;
    loaded = false;
    error = null;
    _notify();
    await load();
  }

  /// Shows [updated], as the server returned it, as the filters allow: an
  /// event they no longer admit (read, under unread only) leaves, and one
  /// they admit again (unread) returns in its newest-first place, unless that
  /// is beyond the pages read, which bring it themselves.
  void replaceEvent(Event updated) {
    final others = [
      for (final e in events)
        if (e.id != updated.id) e,
    ];
    if (!filter.admits(updated)) {
      events = others;
    } else {
      final index = events.indexWhere((e) => e.id == updated.id);
      if (index >= 0) {
        events = [...events]..[index] = updated;
      } else if (_cursor == null || _notAfterLastRead(updated)) {
        final at = others.indexWhere((e) => _isNewer(updated, e));
        events = others..insert(at < 0 ? others.length : at, updated);
      }
    }
    _notify();
  }

  bool _notAfterLastRead(Event event) {
    final last = _lastRead;
    return last != null && !_isNewer(last, event);
  }

  /// Whether [a] comes before [b] in the listing's order: `createdAt`, then
  /// `id`, both descending.
  static bool _isNewer(Event a, Event b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime > 0 : a.id.compareTo(b.id) > 0;
  }

  /// Marks every unread event of this producer read: the ones shown and the
  /// older ones not read yet. `POST /events/read` marks everything up to an
  /// event whatever its producer, which would read events of other producers
  /// that are not shown here, so each is marked on its own. Returns an error
  /// message, or `null` on success.
  Future<String?> markAllRead() async {
    if (markingAll) return null;
    markingAll = true;
    _notify();
    try {
      while (hasMore && loadMoreError == null) {
        await loadMore();
      }
      for (final event in [...events.where((e) => !e.isRead)]) {
        final read = await gateway.call((api) => api.markRead(event.id));
        replaceEvent(read);
      }
      return null;
    } on SignedOutException {
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      markingAll = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
