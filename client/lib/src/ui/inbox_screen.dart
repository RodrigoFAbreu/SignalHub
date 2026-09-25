import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/event.dart';
import '../push/push_registration.dart';
import 'device_screen.dart';
import 'event_screen.dart';
import 'event_style.dart';

/// The connected app: every event, newest first, read page by page from
/// `GET /api/v1/events`, with unread events marked and counted. Tapping an
/// event, or a notification about it, opens its details and marks it read.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_openTappedNotification);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _openTappedNotification(),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_openTappedNotification);
    super.dispose();
  }

  void _openTappedNotification() {
    if (!mounted) return;
    final id = _controller.takeEventToOpen();
    if (id != null) _open(id);
  }

  void _open(String id, [Event? event]) {
    unawaited(_controller.markRead(id));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventScreen(
          load: () => _controller.event(id),
          initial: event,
          markUnread: () => _controller.markUnread(id),
        ),
      ),
    );
  }

  Future<void> _markAllRead() async {
    final error = await _controller.markAllRead();
    if (error != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Scaffold(
      appBar: _appBar(),
      body: RefreshIndicator(
        onRefresh: _controller.refresh,
        child: _list(context),
      ),
    ),
  );

  AppBar _appBar() {
    final unread = _controller.unreadCount ?? 0;
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('SignalHub'),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Badge.count(
              key: const Key('unreadCount'),
              count: unread,
              maxCount: 999,
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          key: const Key('markAllRead'),
          tooltip: 'Mark all as read',
          icon: const Icon(Icons.done_all),
          onPressed: unread > 0 && _controller.events.isNotEmpty
              ? _markAllRead
              : null,
        ),
        PopupMenuButton<void>(
          itemBuilder: (context) => [
            PopupMenuItem(
              key: const Key('device'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DeviceScreen(controller: _controller),
                ),
              ),
              child: const Text('This device'),
            ),
            PopupMenuItem(
              key: const Key('disconnect'),
              onTap: _controller.disconnect,
              child: const Text('Disconnect this device'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _list(BuildContext context) {
    final controller = _controller;
    final banners = [
      if (controller.error case final error?)
        _Banner(
          icon: Icons.error_outline,
          text: error,
          detail: 'Pull down to retry.',
        ),
      if (controller.pushStatus
          case PushStatus.permissionDenied || PushStatus.failed)
        _Banner(
          icon: Icons.notifications_off_outlined,
          text: controller.pushStatus.description,
        ),
    ];
    final events = controller.events;
    final Widget? placeholder = switch ((controller.inboxLoaded, events)) {
      (false, _) when controller.error == null => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      (true, []) => const _Placeholder('No events yet'),
      _ => null,
    };
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: banners.length + (placeholder == null ? events.length + 1 : 1),
      itemBuilder: (context, index) {
        if (index < banners.length) return banners[index];
        if (placeholder != null) return placeholder;
        final i = index - banners.length;
        if (i < events.length) {
          final event = events[i];
          return EventTile(event, onTap: () => _open(event.id, event));
        }
        return _footer();
      },
    );
  }

  Widget _footer() {
    final controller = _controller;
    if (controller.loadMoreError case final error?) {
      return ListTile(
        key: const Key('loadMoreRetry'),
        leading: const Icon(Icons.refresh),
        title: Text(error),
        subtitle: const Text('Tap to retry'),
        onTap: controller.loadMore,
      );
    }
    if (controller.hasMore) {
      // The list builds its footer only once it scrolls near the viewport:
      // that is when the next page is needed.
      if (!controller.loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => controller.loadMore(),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 16);
  }
}

/// One event in the inbox: what it is about, where it came from, and when.
/// Unread events have a bold title and a dot.
class EventTile extends StatelessWidget {
  const EventTile(this.event, {super.key, this.onTap});

  final Event event;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(event.category.icon, color: event.severity.color(colors)),
      title: Text(
        event.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: event.isRead
            ? null
            : const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Text(
        '${event.category.label} · ${event.severity.label} · '
        '${event.producer.name} · ${formatTimestamp(event.createdAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: event.isRead
          ? null
          : Icon(
              Icons.circle,
              key: const Key('unread'),
              size: 12,
              color: colors.primary,
              semanticLabel: 'Unread',
            ),
      onTap: onTap,
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: ListTile(
      leading: Icon(icon),
      title: Text(text),
      subtitle: detail == null ? null : Text(detail!),
    ),
  );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(child: Text(text)),
  );
}
