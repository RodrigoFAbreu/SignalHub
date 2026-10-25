import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/event.dart';
import '../onboarding/onboarding_store.dart';
import '../push/push_registration.dart';
import 'devices_screen.dart';
import 'event_screen.dart';
import 'event_style.dart';
import 'inbox_filter_sheet.dart';
import 'question_words.dart';
import 'link_opener.dart';
import 'whats_new_card.dart';
import 'widgets/banners.dart';
import 'widgets/empty_state.dart';
import 'widgets/skeleton.dart';
import 'widgets/snack.dart';

/// The connected app: every event, newest first, read page by page from
/// `GET /api/v1/events`, with unread events marked and counted, optionally
/// filtered by read state, producer, category and severity. Tapping an
/// event, or a notification about it, opens its details and marks it read;
/// an event's link is opened from there, never straight from the inbox or
/// the notification. A notice about a device is not an event: tapping one
/// opens the devices.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.controller,
    required this.openLink,
  });

  final AppController controller;

  /// Opens an event's link from its screen.
  final LinkOpener openLink;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  AppController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_openTappedNotification);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openTappedNotification();
      // Which producers are subscribed to says what an empty inbox is.
      unawaited(_controller.producers.load());
    });
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
    if (_controller.takeDeviceNoticeToOpen()) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DevicesScreen(controller: _controller),
        ),
      );
    }
  }

  void _open(String id, [Event? event]) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventScreen(
          load: () => _controller.event(id),
          initial: event,
          markOpened: () => _controller.markRead(id),
          setRead: (read) => _controller.setRead(id, read: read),
          openLink: widget.openLink,
          myUserId: _controller.userId,
          answer: (choices, text) =>
              _controller.answerEvent(id, choices: choices, text: text),
          reload: () => _controller.reloadEvent(id),
        ),
      ),
    );
  }

  Future<void> _markAllRead() async {
    final error = await _controller.markAllRead();
    if (error != null && mounted) showAppSnackBar(context, error);
  }

  void _editFilter() {
    // The producers to choose from are the ones this user subscribes to.
    unawaited(_controller.producers.load());
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => InboxFilterSheet(controller: _controller),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_controller, _controller.producers]),
    builder: (context, _) => Scaffold(
      appBar: _appBar(),
      body: Column(
        children: [
          if (_showChips) _InboxChips(controller: _controller),
          if (_controller.filter.narrowsBySheet)
            ActiveFilterBar(controller: _controller, onEdit: _editFilter),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _controller.refresh,
              child: _list(context),
            ),
          ),
        ],
      ),
    ),
  );

  /// The chip row: shown unless the inbox has no events at all and no filter
  /// is on, so the empty inbox is unchanged.
  bool get _showChips {
    final controller = _controller;
    final empty =
        controller.inboxLoaded &&
        controller.events.isEmpty &&
        !controller.hasMore &&
        !controller.filter.isActive;
    return !empty && !(controller.error != null && !controller.inboxLoaded);
  }

  AppBar _appBar() {
    final unread = _controller.unreadCount ?? 0;
    return AppBar(
      title: const Text('SignalHub'),
      actions: [
        IconButton(
          key: const Key('filter'),
          tooltip: 'Filter events',
          isSelected: _controller.filter.isActive,
          icon: const Icon(Icons.filter_list),
          selectedIcon: const Icon(Icons.filter_alt),
          onPressed: _editFilter,
        ),
        // Nothing to mark while there are no events, and no change is made
        // while the server cannot be reached.
        if (_controller.events.isNotEmpty)
          IconButton(
            key: const Key('markAllRead'),
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all),
            onPressed:
                unread > 0 &&
                    _controller.canMarkAllRead &&
                    !_controller.serverUnreachable
                ? _markAllRead
                : null,
          ),
      ],
    );
  }

  /// The top of the list: what changed once, and what is wrong with reading
  /// it. A refresh that failed leaves the older list under a neutral banner
  /// with its time.
  List<Widget> _banners() {
    final controller = _controller;
    final loadedAt = controller.inboxLoadedAt;
    final time = loadedAt == null ? '' : formatClock(loadedAt);
    return [
      if (controller.onboarding == OnboardingStep.whatsNew)
        WhatsNewCard(controller: controller),
      if (controller.inboxLoaded && controller.error != null)
        if (controller.serverUnreachable)
          AppBanner(
            icon: Icons.cloud_off,
            message:
                "You're offline. This is the list from $time. Changes are "
                "paused until you're back.",
          )
        else
          AppBanner(
            icon: Icons.history,
            message: "Couldn't refresh. This is the list from $time.",
            actionLabel: 'Try again',
            onAction: controller.refresh,
          ),
      // An unreachable server is the one thing to fix; push waits for it.
      if (!controller.serverUnreachable)
        if (controller.pushStatus
            case PushStatus.permissionDenied ||
                PushStatus.failed ||
                PushStatus.unsupported ||
                PushStatus.restartRequired)
          AppBanner(
            icon: Icons.notifications_off_outlined,
            message: controller.pushStatus.description,
          ),
    ];
  }

  Widget _list(BuildContext context) {
    final controller = _controller;
    final events = controller.events;
    final banners = _banners();
    final Widget? placeholder = switch ((controller.inboxLoaded, events)) {
      (false, _) when controller.error == null => const SkeletonRows(
        count: 6,
        circleLeading: false,
      ),
      (false, _) => EmptyState(
        icon: Icons.cloud_off,
        title: "Couldn't load events",
        body: controller.serverUnreachable
            ? 'Check your connection and try again.'
            : 'SignalHub had a problem. Try again in a moment.',
        actionLabel: 'Try again',
        actionIcon: Icons.refresh,
        onAction: controller.refresh,
      ),
      // An older server may answer a page with only read events for the
      // unread-only view: the footer reads on.
      (true, []) when !controller.hasMore => _emptyInbox(),
      _ => null,
    };
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (banners.isNotEmpty)
          SliverToBoxAdapter(child: Column(children: banners)),
        if (placeholder == null)
          SliverList.builder(
            itemCount: events.length + 1,
            itemBuilder: (context, i) {
              if (i < events.length) {
                final event = events[i];
                return EventTile(
                  event,
                  myUserId: controller.userId,
                  onTap: () => _open(event.id, event),
                );
              }
              return _footer();
            },
          )
        else if (placeholder is SkeletonRows)
          SliverToBoxAdapter(child: placeholder)
        else
          SliverFillRemaining(hasScrollBody: false, child: placeholder),
      ],
    );
  }

  /// Nothing in the inbox: a filter that matches nothing, nothing subscribed
  /// to (which is the one thing that fills it), or subscriptions that have
  /// sent nothing yet.
  Widget _emptyInbox() {
    final controller = _controller;
    final filter = controller.filter;
    if (filter.toAnswer && !filter.unreadOnly && !filter.narrowsBySheet) {
      return EmptyState(
        icon: Icons.task_alt,
        title: 'Nothing to answer',
        body:
            'Questions you can answer show up here until someone answers '
            'them or they close.',
        actionLabel: 'Show all events',
        onAction: () => controller.setFilter(filter.copyWith(toAnswer: false)),
      );
    }
    if (filter.isActive) {
      return EmptyState(
        icon: Icons.filter_list_off,
        title: 'No events match these filters',
        actionLabel: 'Clear filters',
        onAction: controller.clearFilter,
      );
    }
    final producers = controller.producers;
    final nothingSubscribed =
        producers.list.hasValue && producers.subscribed.isEmpty;
    if (!nothingSubscribed) {
      return const EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Nothing new from your producers',
        body: 'New events from the producers you subscribe to show up here.',
      );
    }
    return EmptyState(
      icon: Icons.inbox_outlined,
      title: 'No events yet',
      body: 'Events show up here once you subscribe to a producer.',
      actionLabel: 'Find producers',
      actionIcon: Icons.sensors,
      onAction: () => controller.selectTab(HomeTab.producers),
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
/// Unread events have a bold title and a dot; events with a link, a link
/// icon.
class EventTile extends StatelessWidget {
  const EventTile(this.event, {super.key, this.onTap, this.myUserId});

  final Event event;
  final VoidCallback? onTap;

  /// Who this is, so an answer of theirs reads _You answered_.
  final String? myUserId;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final line = questionLine(event, myUserId: myUserId);
    return ListTile(
      isThreeLine: line != null,
      leading: Icon(event.category.icon, color: event.severity.color(colors)),
      title: Text(
        event.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: event.isRead
            ? null
            : const TextStyle(fontWeight: FontWeight.bold),
      ),
      // The time is never cut: a long producer name or severity gives way.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${event.category.label} · ${event.severity.label} · '
                  '${event.producer.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (event.link != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.link,
                  key: Key('hasLink'),
                  size: 16,
                  semanticLabel: 'Has a link',
                ),
              ],
              const SizedBox(width: 8),
              Text(
                formatTimestamp(event.createdAt),
                key: const Key('eventTime'),
                maxLines: 1,
                softWrap: false,
              ),
            ],
          ),
          if (line != null) _QuestionLineView(line),
        ],
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

/// The line under a question's row: an icon and words, never the icon alone.
/// One line: a long label ends with an ellipsis, and the whole line is the
/// row's accessible name.
class _QuestionLineView extends StatelessWidget {
  const _QuestionLineView(this.line);

  final QuestionLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = line.quiet ? colors.onSurfaceVariant : colors.primary;
    return Padding(
      key: const Key('questionLine'),
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(line.icon, size: 18, color: color)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              line.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: line.quiet ? null : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// _Unread_ and _To answer_: the only chips of the inbox. _To answer_ shows
/// only while its count is above 0 or while it is on, so a person who never
/// gets questions never sees it.
class _InboxChips extends StatelessWidget {
  const _InboxChips({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final filter = controller.filter;
    final count = controller.toAnswerCount;
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilterChip(
              key: const Key('chipUnread'),
              label: const Text('Unread'),
              selected: filter.unreadOnly,
              onSelected: (on) =>
                  controller.setFilter(filter.copyWith(unreadOnly: on)),
            ),
            if (count > 0 || filter.toAnswer)
              FilterChip(
                key: const Key('chipToAnswer'),
                label: Semantics(
                  label: count > 0 ? 'To answer, $count' : 'To answer',
                  excludeSemantics: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('To answer'),
                      if (count > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '$count',
                          style: TextStyle(
                            color: filter.toAnswer ? null : colors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                selected: filter.toAnswer,
                onSelected: (on) =>
                    controller.setFilter(filter.copyWith(toAnswer: on)),
              ),
          ],
        ),
      ),
    );
  }
}
