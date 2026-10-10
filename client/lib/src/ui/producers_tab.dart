import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/producers_controller.dart';
import 'new_producer_screen.dart';
import 'producer_row_tile.dart';
import 'producer_screen.dart';
import 'widgets/app_bar_title.dart';
import 'widgets/banners.dart';
import 'widgets/empty_state.dart';
import 'widgets/search_field.dart';
import 'widgets/skeleton.dart';
import 'widgets/snack.dart';

/// Which producers the Producers tab lists.
enum ProducerFilter {
  all('All'),
  yours('Yours'),
  subscribed('Subscribed'),
  canSubscribe('Can subscribe');

  const ProducerFilter(this.label);

  final String label;

  bool admits(ProducerRow row) => switch (this) {
    all => true,
    yours => row.isYours,
    subscribed => row.subscribed,
    canSubscribe => !row.subscribed,
  };
}

/// The Producers tab: search, single-choice filter chips and every producer
/// this user sees, with the bell that subscribes in place and a button for a
/// new producer. Reading works offline; writes are greyed with the reason
/// said once at the top.
class ProducersTab extends StatefulWidget {
  const ProducersTab({super.key, required this.controller});

  final AppController controller;

  @override
  State<ProducersTab> createState() => _ProducersTabState();
}

class _ProducersTabState extends State<ProducersTab> {
  final _search = TextEditingController();
  var _filter = ProducerFilter.all;
  var _query = '';
  var _shown = true;

  AppController get _app => widget.controller;
  ProducersController get _producers => _app.producers;

  @override
  void initState() {
    super.initState();
    _app.addListener(_reloadWhenShown);
    // Not while building: reading notifies the controller's listeners.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _producers.load();
    });
  }

  @override
  void dispose() {
    _app.removeListener(_reloadWhenShown);
    _search.dispose();
    super.dispose();
  }

  /// The list is read again each time the tab comes to the front, so a
  /// producer that gained or lost access shows up or goes.
  void _reloadWhenShown() {
    final shown = _app.tab == HomeTab.producers;
    if (shown && !_shown) _producers.load();
    _shown = shown;
  }

  Future<void> _refresh() => _producers.load();

  List<ProducerRow> _visibleRows() {
    final query = _query.trim().toLowerCase();
    return [
      for (final row in _producers.rows)
        if (_filter.admits(row) &&
            (query.isEmpty || row.name.toLowerCase().contains(query)))
          row,
    ];
  }

  Future<void> _openProducer(ProducerRow row) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProducerScreen(controller: _app, producerId: row.id),
      ),
    );
    // Whatever the screen changed is on the list when it comes back.
    if (mounted) unawaited(_producers.load());
  }

  void _newProducer() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NewProducerScreen(controller: _app),
      ),
    );
  }

  Future<void> _setSubscribed(ProducerRow row, bool subscribed) async {
    final name = row.name;
    final outcome = await _producers.setSubscribed(
      row.id,
      subscribed: subscribed,
    );
    if (!mounted) return;
    switch (outcome) {
      case SubscriptionOutcome.changed:
        // The inbox holds, or stops holding, the producer's events.
        unawaited(_app.reloadInbox());
        showAppSnackBar(
          context,
          subscribed
              ? 'Subscribed to $name. Its older events are in your inbox too.'
              : 'Unsubscribed from $name. Its events leave your inbox.',
          actionLabel: 'Undo',
          onAction: () => _setSubscribed(row, !subscribed),
        );
      case SubscriptionOutcome.failed:
        showAppSnackBar(
          context,
          subscribed
              ? "Couldn't subscribe to $name. Try again."
              : "Couldn't unsubscribe from $name. Try again.",
          actionLabel: 'Retry',
          onAction: () => _setSubscribed(row, subscribed),
        );
      case SubscriptionOutcome.gone || SubscriptionOutcome.ignored:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_producers, _app]),
    builder: (context, _) {
      final list = _producers.list;
      final offline = list.hasValue && list.offline;
      final rows = list.hasValue ? _visibleRows() : const <ProducerRow>[];
      final empty = list.hasValue ? _emptyState(rows) : null;
      final banner = _banner(offline);
      return Scaffold(
        // Filtering is used constantly: the button comes and goes at once.
        floatingActionButtonAnimator: FloatingActionButtonAnimator.noAnimation,
        appBar: AppBar(
          title: AppBarTitle.text(context, 'Producers'),
          toolbarHeight: AppBarTitle.height(context),
        ),
        // The button is the empty state's own while that offers one.
        floatingActionButton:
            list.hasValue && !(empty?.offersNewProducer ?? false)
            ? _NewProducerButton(onPressed: offline ? null : _newProducer)
            : null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSearchField(
              controller: _search,
              hint: 'Find a producer',
              bottomPadding: list.hasValue ? 0 : 8,
              onChanged: (value) => setState(() => _query = value),
            ),
            if (list.hasValue)
              _FilterChips(
                selected: _filter,
                onSelected: (filter) => setState(() => _filter = filter),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: _content(rows, empty, offline, banner),
              ),
            ),
          ],
        ),
      );
    },
  );

  String _time(DateTime? at) {
    final t = (at ?? DateTime.now()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  /// Why the list may be old, or why changes are paused, said once above the
  /// list; it scrolls with the list so that large text never crowds it out.
  Widget? _banner(bool offline) {
    final list = _producers.list;
    if (offline) {
      return AppBanner(
        icon: Icons.cloud_off,
        message:
            "You're offline. This is the list from ${_time(list.loadedAt)}. "
            "Changes are paused until you're back.",
      );
    }
    if (list.stale) {
      return AppBanner(
        icon: Icons.cloud_off,
        message:
            "Couldn't refresh the list. This is the one from "
            '${_time(list.loadedAt)}.',
        actionLabel: 'Try again',
        onAction: _refresh,
      );
    }
    return null;
  }

  Widget _content(
    List<ProducerRow> rows,
    _Empty? empty,
    bool offline,
    Widget? banner,
  ) {
    if (!_producers.list.hasValue) {
      return _producers.list.failedWithoutList
          ? _scrollable(_loadFailed())
          : const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: SkeletonRows(count: 4),
            );
    }
    if (empty != null) return _scrollable(empty.build(), banner);
    final muted = {
      ..._app.registration?.pushPreferences?.mutedProducerIds ?? const [],
    };
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      // Clear of the button that floats over the last row.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: rows.length + (banner == null ? 0 : 1),
      itemBuilder: (context, i) {
        if (banner != null) {
          if (i == 0) return banner;
          i--;
        }
        final row = rows[i];
        return ProducerRowTile(
          key: ValueKey(row.id),
          row: row,
          mutedOnDevice: muted.contains(row.id),
          changingTo: _producers.changingTo(row.id),
          onOpen: () => _openProducer(row),
          onBell: offline ? null : () => _setSubscribed(row, !row.subscribed),
        );
      },
    );
  }

  /// A scroll view that pulls to refresh whatever it holds, and gives it the
  /// whole space, under [banner] if there is one.
  Widget _scrollable(Widget child, [Widget? banner]) => LayoutBuilder(
    builder: (context, box) => ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ?banner,
        // The drawings lift the empty state 40 dp above the middle.
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

  Widget _loadFailed() {
    final serverProblem = _producers.list.error?.statusCode != null;
    return EmptyState(
      icon: Icons.cloud_off,
      title: "Couldn't load producers",
      body: serverProblem
          ? 'SignalHub had a problem. Try again in a moment.'
          : 'Check your connection and try again.',
      actionLabel: 'Try again',
      actionIcon: Icons.refresh,
      onAction: _refresh,
    );
  }

  /// What the list says instead of rows, or `null` when there are rows.
  _Empty? _emptyState(List<ProducerRow> rows) {
    if (rows.isNotEmpty) return null;
    if (_query.trim().isNotEmpty) {
      return _Empty(
        icon: Icons.search_off,
        title: 'No producers match',
        body:
            'Nothing you can see is named “${_query.trim()}”. '
            'Check the spelling, or clear the search.',
        actionLabel: 'Clear search',
        onAction: () => setState(() {
          _search.clear();
          _query = '';
        }),
      );
    }
    if (_producers.rows.isEmpty || _filter == ProducerFilter.yours) {
      return _Empty(
        icon: _filter == ProducerFilter.yours
            ? Icons.filter_list_off
            : Icons.sensors,
        title: _filter == ProducerFilter.yours
            ? "You don't have a producer yet"
            : 'No producers yet',
        body: _filter == ProducerFilter.yours
            ? 'A producer sends events to you and, if you let them, to '
                  'others. Each one has its own key.'
            : 'Nobody has shared a producer with you, and there is no '
                  'public one on this server. Make your own to send '
                  'yourself events.',
        actionLabel: 'New producer',
        actionIcon: Icons.add,
        onAction: _newProducer,
        offersNewProducer: true,
      );
    }
    void showAll() => setState(() => _filter = ProducerFilter.all);
    return switch (_filter) {
      ProducerFilter.subscribed => _Empty(
        icon: Icons.notifications_off_outlined,
        title: "You aren't subscribed to any producer",
        body:
            'Subscribe with the bell on a producer, and its events show '
            'up in your inbox.',
        actionLabel: 'Show all',
        onAction: showAll,
      ),
      _ => _Empty(
        icon: Icons.task_alt,
        title: 'Nothing else to subscribe to',
        body:
            'You get events from every producer you can see. New public '
            'producers and ones shared with you will appear here.',
        actionLabel: 'Show all',
        onAction: showAll,
      ),
    };
  }
}

class _Empty {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon,
    this.offersNewProducer = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final IconData? actionIcon;
  final VoidCallback onAction;

  /// Whether its button is _New producer_, so the floating one is hidden.
  final bool offersNewProducer;

  Widget build() => EmptyState(
    icon: icon,
    title: title,
    body: body,
    actionLabel: actionLabel,
    actionIcon: actionIcon,
    onAction: onAction,
  );
}

/// The _New producer_ button, 16 dp above the bar; greyed while offline.
class _NewProducerButton extends StatelessWidget {
  const _NewProducerButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onPressed == null ? 0.38 : 1,
    child: FloatingActionButton.extended(
      heroTag: 'new-producer',
      // Tonal and flat, as drawn.
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      onPressed: onPressed ?? () {},
      icon: const Icon(Icons.add),
      label: const Text('New producer'),
    ),
  );
}

/// Single-choice chips that scroll sideways, a check on the selected one.
/// Each has a 48 dp hit area around its 32 dp look.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.selected, required this.onSelected});

  final ProducerFilter selected;
  final ValueChanged<ProducerFilter> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final filter in ProducerFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              key: Key('producerFilter-${filter.name}'),
              label: Text(filter.label),
              // 32 dp to look at, 48 dp to hit.
              padding: const EdgeInsets.symmetric(vertical: 5),
              selected: filter == selected,
              showCheckmark: true,
              onSelected: (_) => onSelected(filter),
            ),
          ),
      ],
    ),
  );
}
