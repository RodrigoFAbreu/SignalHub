import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/producer_events_controller.dart';
import '../models/event.dart';
import '../models/inbox_filter.dart';
import 'event_screen.dart';
import 'inbox_screen.dart' show EventTile;
import 'link_opener.dart' as links;
import 'widgets/app_bar_title.dart';
import 'widgets/empty_state.dart';
import 'widgets/skeleton.dart';
import 'widgets/snack.dart';

/// The events of one producer: the inbox narrowed to it, opened from the
/// producer's screen. The title is the producer's name, the producer is a
/// chip that can be removed (which leaves for the full inbox), and the other
/// filters (unread only, category, severity) combine with it.
///
/// It keeps its own list, so it never changes what the Inbox tab shows.
class ProducerEventsScreen extends StatefulWidget {
  const ProducerEventsScreen({
    super.key,
    required this.controller,
    required this.producerId,
    required this.producerName,
    this.openLink = links.openLink,
  });

  final AppController controller;
  final String producerId;
  final String producerName;

  /// Opens an event's link from its screen; tests replace the platform.
  final links.LinkOpener openLink;

  @override
  State<ProducerEventsScreen> createState() => _ProducerEventsScreenState();
}

class _ProducerEventsScreenState extends State<ProducerEventsScreen> {
  late final ProducerEventsController _events = ProducerEventsController(
    gateway: widget.controller,
    producerId: widget.producerId,
  );

  String get _name => widget.producerName;

  @override
  void initState() {
    super.initState();
    unawaited(_events.load());
  }

  @override
  void dispose() {
    _events.dispose();
    super.dispose();
  }

  /// The producer's chip is removed: the full inbox, as it was.
  void _leaveForInbox() {
    widget.controller.selectTab(HomeTab.inbox);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _open(Event event) {
    final app = widget.controller;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventScreen(
          load: () => app.event(event.id),
          initial: event,
          markOpened: () => _keepInList(app.markRead(event.id)),
          setRead: (read) => _keepInList(app.setRead(event.id, read: read)),
          openLink: widget.openLink,
        ),
      ),
    );
  }

  /// Shows a read-state change here too: the app changes the Inbox tab's list
  /// and the unread count, this list is its own.
  Future<({Event? event, String? error})> _keepInList(
    Future<({Event? event, String? error})> change,
  ) async {
    final result = await change;
    if (result.event case final event? when mounted) {
      _events.replaceEvent(event);
    }
    return result;
  }

  Future<void> _markAllRead() async {
    final error = await _events.markAllRead();
    unawaited(widget.controller.reloadInbox());
    if (error != null && mounted) showAppSnackBar(context, error);
  }

  void _editFilter() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(events: _events, producerName: _name),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _events,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: AppBarTitle.withSubtitle(
          context,
          _name,
          'Events from this producer',
        ),
        toolbarHeight: AppBarTitle.height(context, subtitle: true),
        // The title starts where the drawing has it, 56 dp from the edge.
        titleSpacing: 0,
        actions: [
          IconButton(
            key: const Key('filter'),
            tooltip: 'Filter events',
            isSelected: _events.narrowed,
            icon: const Icon(Icons.filter_list),
            selectedIcon: const Icon(Icons.filter_alt),
            onPressed: _editFilter,
          ),
          IconButton(
            key: const Key('markAllRead'),
            tooltip: 'Mark all as read',
            icon: const Icon(Icons.done_all),
            onPressed: _events.hasUnread && !_events.markingAll
                ? _markAllRead
                : null,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FilterChips(
            producerName: _name,
            extras: _events.extras,
            onRemoveProducer: _leaveForInbox,
            onChange: _events.setExtras,
          ),
          Expanded(
            child: RefreshIndicator(onRefresh: _events.load, child: _body()),
          ),
        ],
      ),
    ),
  );

  Widget _body() {
    final events = _events;
    if (!events.loaded) {
      return events.error != null
          ? _scrollable(
              EmptyState(
                icon: Icons.cloud_off,
                title: "Couldn't load events",
                body: events.error!.statusCode == null
                    ? 'Check your connection and try again.'
                    : 'SignalHub had a problem. Try again in a moment.',
                actionLabel: 'Try again',
                actionIcon: Icons.refresh,
                onAction: events.load,
              ),
            )
          : const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: SkeletonRows(count: 4, circleLeading: false),
            );
    }
    if (events.events.isEmpty && !events.hasMore) {
      return _scrollable(_empty());
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: events.events.length + 1,
      itemBuilder: (context, i) => i < events.events.length
          ? EventTile(events.events[i], onTap: () => _open(events.events[i]))
          : _footer(),
    );
  }

  Widget _footer() {
    final events = _events;
    if (events.loadMoreError case final error?) {
      return ListTile(
        key: const Key('loadMoreRetry'),
        leading: const Icon(Icons.refresh),
        title: Text(error),
        subtitle: const Text('Tap to retry'),
        onTap: events.loadMore,
      );
    }
    if (events.hasMore) {
      // The list builds its footer only once it scrolls near the viewport:
      // that is when the next page is needed.
      if (!events.loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) => events.loadMore());
      }
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 16);
  }

  Widget _empty() {
    final extras = _events.extras;
    if (extras.unreadOnly) {
      return EmptyState(
        icon: Icons.inbox,
        title: 'Nothing unread from $_name.',
        actionLabel: 'Show all',
        onAction: () => _events.setExtras(extras.copyWith(unreadOnly: false)),
      );
    }
    if (_events.narrowed) {
      return EmptyState(
        icon: Icons.inbox,
        title: 'No events match these filters',
        body: 'Nothing from $_name fits what you chose.',
        actionLabel: 'Clear filters',
        onAction: () => _events.setExtras(InboxFilter.none),
      );
    }
    return EmptyState(
      icon: Icons.inbox,
      title: 'No events from $_name yet',
      body: 'When it sends one, it shows up here.',
      actionLabel: 'Back to $_name',
      onAction: () => Navigator.of(context).pop(),
    );
  }

  /// Gives [child] the whole space, in a scroll view that pulls to refresh.
  Widget _scrollable(Widget child) => LayoutBuilder(
    builder: (context, box) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: box.maxHeight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 80),
            child: child,
          ),
        ),
      ],
    ),
  );
}

/// The producer as a chip that can be removed, and the other filters in
/// force, each removable the same way.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.producerName,
    required this.extras,
    required this.onRemoveProducer,
    required this.onChange,
  });

  final String producerName;
  final InboxFilter extras;
  final VoidCallback onRemoveProducer;
  final ValueChanged<InboxFilter> onChange;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        _RemovableChip(
          key: const Key('producerChip'),
          label: producerName,
          onRemove: onRemoveProducer,
        ),
        if (extras.unreadOnly)
          _RemovableChip(
            label: 'Unread',
            onRemove: () => onChange(extras.copyWith(unreadOnly: false)),
          ),
        for (final category in EventCategory.values)
          if (extras.categories.contains(category))
            _RemovableChip(
              label: category.label,
              onRemove: () => onChange(
                extras.copyWith(
                  categories: toggled(extras.categories, category),
                ),
              ),
            ),
        for (final severity in EventSeverity.values)
          if (extras.severities.contains(severity))
            _RemovableChip(
              label: severity.label,
              onRemove: () => onChange(
                extras.copyWith(
                  severities: toggled(extras.severities, severity),
                ),
              ),
            ),
      ],
    ),
  );
}

/// A selected chip (secondaryContainer, a check) with an x, 48 dp to hit,
/// named `Remove filter NAME`. The chip is 32 dp to look at.
class _RemovableChip extends StatelessWidget {
  const _RemovableChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = colors.onSecondaryContainer;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      // A long name ends in an ellipsis inside the screen's width.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width - 32,
        ),
        child: Stack(
          children: [
            // The look: 32 dp inside the 48 dp row, ending under the x.
            Positioned.fill(
              top: 8,
              bottom: 8,
              right: 7,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 8),
                Icon(Icons.check, size: 18, color: foreground),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Remove filter $label',
                  excludeSemantics: true,
                  onTap: onRemove,
                  child: Tooltip(
                    message: 'Remove filter $label',
                    excludeFromSemantics: true,
                    child: InkResponse(
                      onTap: onRemove,
                      customBorder: const CircleBorder(),
                      radius: 24,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.close, size: 18, color: foreground),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Unread only, categories and severities for this producer's events. Every
/// change applies at once.
class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.events, required this.producerName});

  final ProducerEventsController events;
  final String producerName;

  static final _categories = [
    for (final c in EventCategory.values)
      if (c != EventCategory.unknown) c,
  ];

  static final _severities = [
    for (final s in EventSeverity.values)
      if (s != EventSeverity.unknown) s,
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: events,
    builder: (context, _) {
      final extras = events.extras;
      void apply(InboxFilter next) => events.setExtras(next);
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            ListTile(
              title: Text(
                'Show from $producerName',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              trailing: TextButton(
                key: const Key('clearFiltersInSheet'),
                onPressed: events.narrowed
                    ? () => apply(InboxFilter.none)
                    : null,
                child: const Text('Clear all'),
              ),
            ),
            SwitchListTile(
              key: const Key('unreadOnly'),
              title: const Text('Unread only'),
              value: extras.unreadOnly,
              onChanged: (value) => apply(extras.copyWith(unreadOnly: value)),
            ),
            const _Heading('Categories'),
            _Chips([
              for (final category in _categories)
                FilterChip(
                  key: Key('filterCategory-${category.wireName}'),
                  label: Text(category.label),
                  selected: extras.categories.contains(category),
                  onSelected: (_) => apply(
                    extras.copyWith(
                      categories: toggled(extras.categories, category),
                    ),
                  ),
                ),
            ]),
            const _Heading('Severities'),
            _Chips([
              for (final severity in _severities)
                FilterChip(
                  key: Key('filterSeverity-${severity.wireName}'),
                  label: Text(severity.label),
                  selected: extras.severities.contains(severity),
                  onSelected: (_) => apply(
                    extras.copyWith(
                      severities: toggled(extras.severities, severity),
                    ),
                  ),
                ),
            ]),
          ],
        ),
      );
    },
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Chips extends StatelessWidget {
  const _Chips(this.chips);

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Wrap(spacing: 8, runSpacing: 4, children: chips),
  );
}
