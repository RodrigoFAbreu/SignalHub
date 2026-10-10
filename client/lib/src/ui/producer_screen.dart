import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/own_producers_controller.dart';
import '../models/producers.dart';
import '../models/users.dart';
import '../settings/settings_groups.dart';
import 'allow_list_screen.dart';
import 'own_producer_view.dart';
import 'producer_dates.dart';
import 'producer_dialogs.dart';
import 'producer_events_screen.dart';
import 'producer_key_screen.dart';
import 'other_producer_view.dart';
import 'text_sharer.dart';
import 'widgets/banners.dart';
import 'widgets/empty_state.dart';
import 'widgets/producer_parts.dart';
import 'widgets/skeleton.dart';
import 'widgets/snack.dart';

enum _Kind { loading, own, other, gone, failed }

/// A producer's own screen: everything about one this user owns, or the
/// subscription to one somebody else owns. Which of the two it is, the
/// server decides: it answers `404` for a producer this user does not own.
/// When it answers `404` for both, the producer is no longer available.
class ProducerScreen extends StatefulWidget {
  const ProducerScreen({
    super.key,
    required this.controller,
    required this.producerId,
    this.share = shareText,
  });

  final AppController controller;
  final String producerId;
  final TextSharer share;

  @override
  State<ProducerScreen> createState() => _ProducerScreenState();
}

class _ProducerScreenState extends State<ProducerScreen> {
  _Kind _kind = _Kind.loading;
  OwnProducer? _own;
  VisibleProducer? _other;

  /// Why the first read failed, for the screen that says so.
  ProducerFailure? _failure;

  /// Why the latest refresh failed while the screen shows what it read
  /// before; `null` if it worked.
  ProducerFailure? _staleBecause;
  DateTime? _loadedAt;

  /// Whether a change is in flight: taps are ignored until it ends.
  bool _busy = false;

  /// What the visibility control shows while its change is in flight.
  ProducerVisibility? _pendingVisibility;

  AppController get _controller => widget.controller;
  OwnProducersController get _ownProducers => _controller.ownProducers;
  String get _id => widget.producerId;

  /// Reading works but nothing that writes does while the connection is
  /// down: the controls are greyed and the banner says why.
  bool get _paused => _staleBecause == ProducerFailure.offline;

  @override
  void initState() {
    super.initState();
    _ownProducers.addListener(_followLists);
    _controller.producers.addListener(_followLists);
    // Not while building: reading notifies the listeners of the lists.
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  @override
  void dispose() {
    _ownProducers.removeListener(_followLists);
    _controller.producers.removeListener(_followLists);
    super.dispose();
  }

  /// The lists change under the screen (a bell, a refresh): it shows them.
  void _followLists() {
    if (!mounted) return;
    setState(() {
      _own = _ownProducers.byId(_id) ?? _own;
      if (_kind == _Kind.other) {
        _other = _controller.producers.byId(_id) ?? _other;
      }
    });
  }

  Future<void> _resolve() async {
    final mine = _ownProducers.byId(_id);
    final visible = _controller.producers.byId(_id);
    if (mine != null) {
      setState(() {
        _own = mine;
        _kind = _Kind.own;
      });
      await _refreshOwn();
    } else if (visible != null && visible.owner.id != _controller.userId) {
      setState(() {
        _other = visible;
        _kind = _Kind.other;
      });
      await _refreshOther();
    } else {
      await _discover();
    }
  }

  /// A producer not in the lists: the server tells whether it is this user's.
  Future<void> _discover() async {
    final outcome = await _ownProducers.read(_id);
    if (!mounted) return;
    if (outcome.value case final producer?) {
      setState(() {
        _own = producer;
        _kind = _Kind.own;
        _loadedAt = DateTime.now();
      });
      return;
    }
    if (outcome.failure == ProducerFailure.notFound) {
      await _discoverVisible();
      return;
    }
    if (outcome.failure == ProducerFailure.signedOut) return;
    setState(() {
      _kind = _Kind.failed;
      _failure = outcome.failure;
    });
  }

  /// Not this user's: it is somebody else's producer they see, or none.
  Future<void> _discoverVisible() async {
    await _controller.producers.load();
    if (!mounted) return;
    final visible = _controller.producers.byId(_id);
    final error = _controller.producers.list.error;
    setState(() {
      if (visible != null) {
        _other = visible;
        _kind = _Kind.other;
        _loadedAt = DateTime.now();
        _staleBecause = error == null ? null : _failureOfList();
      } else if (error != null) {
        _kind = _Kind.failed;
        _failure = _failureOfList();
      } else {
        _kind = _Kind.gone;
      }
    });
  }

  ProducerFailure _failureOfList() {
    final status = _controller.producers.list.error?.statusCode;
    return status == null
        ? ProducerFailure.offline
        : status >= 500
        ? ProducerFailure.server
        : ProducerFailure.other;
  }

  Future<void> _refreshOwn() async {
    final outcome = await _ownProducers.read(_id);
    if (!mounted) return;
    setState(() {
      switch (outcome.failure) {
        case null:
          _own = outcome.value;
          _staleBecause = null;
          _loadedAt = DateTime.now();
        case ProducerFailure.notFound:
          _kind = _Kind.gone;
        case ProducerFailure.signedOut:
          break;
        case final failure:
          _staleBecause = failure;
      }
    });
  }

  Future<void> _refreshOther() async {
    await _controller.producers.load();
    if (!mounted) return;
    final error = _controller.producers.list.error;
    final visible = _controller.producers.byId(_id);
    setState(() {
      if (error != null) {
        _staleBecause = _failureOfList();
        return;
      }
      _staleBecause = null;
      _loadedAt = DateTime.now();
      if (visible == null) {
        _kind = _Kind.gone;
      } else {
        _other = visible;
      }
    });
  }

  Future<void> _refresh() => switch (_kind) {
    _Kind.own => _refreshOwn(),
    _Kind.other => _refreshOther(),
    _ => _retry(),
  };

  Future<void> _retry() async {
    setState(() {
      _kind = _Kind.loading;
      _failure = null;
    });
    await _resolve();
  }

  /// The visible producers hold this producer's name, visibility and
  /// subscription too: they follow every change made here.
  void _syncVisible() => unawaited(_controller.producers.load());

  // -- changes ---------------------------------------------------------

  /// Runs a change to this producer, ignoring taps meanwhile. A producer that
  /// is gone ends on its own screen; any other failure is a snackbar with
  /// Retry that says nothing changed. Returns whether it worked.
  Future<bool> _change(
    Future<ProducerOutcome<OwnProducer>> Function() change, {
    required String doing,
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    final outcome = await change();
    if (!mounted) return false;
    setState(() {
      _busy = false;
      _pendingVisibility = null;
      if (outcome.value case final producer?) _own = producer;
      if (outcome.failure == ProducerFailure.notFound) _kind = _Kind.gone;
    });
    if (outcome.ok) {
      _syncVisible();
      return true;
    }
    if (outcome.failure == ProducerFailure.disabledByHost) {
      unawaited(_refreshOwn());
    }
    final message = outcome.failure == ProducerFailure.notFound
        ? null
        : outcome.message(doing);
    if (message != null) {
      showAppSnackBar(
        context,
        message,
        actionLabel:
            outcome.failure == ProducerFailure.forbidden ||
                outcome.failure == ProducerFailure.disabledByHost
            ? null
            : 'Retry',
        onAction: () => _change(change, doing: doing),
      );
    }
    return false;
  }

  Future<void> _setSubscribed(bool subscribed, String name) async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await _ownProducers.setSubscribed(
      _id,
      subscribed: subscribed,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (outcome.value case final visible?) {
        if (_kind == _Kind.other) _other = visible;
        _own = _own?.withSubscribed(visible.subscribed);
      }
      if (outcome.failure == ProducerFailure.notFound) _kind = _Kind.gone;
    });
    if (outcome.ok) {
      _syncVisible();
      showAppSnackBar(
        context,
        subscribed
            ? 'Subscribed to $name. Its older events are in your inbox too.'
            : 'Unsubscribed from $name. Its events leave your inbox.',
        actionLabel: 'Undo',
        onAction: () => _setSubscribed(!subscribed, name),
      );
    } else if (outcome.failure != ProducerFailure.notFound &&
        outcome.failure != ProducerFailure.signedOut) {
      showAppSnackBar(
        context,
        subscribed
            ? "Couldn't subscribe to $name. Try again."
            : "Couldn't unsubscribe from $name. Try again.",
        actionLabel: 'Retry',
        onAction: () => _setSubscribed(subscribed, name),
      );
    }
  }

  Future<void> _rename(OwnProducer producer) async {
    final renamed = await ProducerDialogs.rename(
      context,
      controller: _ownProducers,
      producer: producer,
    );
    if (renamed == null || !mounted) return;
    setState(() => _own = renamed);
    _syncVisible();
  }

  Future<void> _setVisibility(
    OwnProducer producer,
    ProducerVisibility next,
  ) async {
    if (_busy || next == producer.visibility) return;
    if (next == ProducerVisibility.private &&
        !await ProducerDialogs.makePrivate(context, producer)) {
      return;
    }
    if (!mounted) return;
    setState(() => _pendingVisibility = next);
    await _change(
      () => _ownProducers.setVisibility(_id, next),
      doing: 'change who can see ${producer.name}',
    );
  }

  Future<void> _revokeKey(OwnProducer producer, ProducerKeyInfo key) async {
    if (!await ProducerDialogs.revokeKey(
      context,
      key: key,
      producer: producer,
    )) {
      return;
    }
    await _change(
      () => _ownProducers.revokeKey(_id, key.id),
      doing: 'revoke ${ProducerDialogs.keyLabel(key)}',
    );
  }

  Future<void> _newKey(OwnProducer producer) async {
    if (_busy) return;
    setState(() => _busy = true);
    final outcome = await _ownProducers.issueKey(_id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (outcome.value case final issued?) {
      setState(() => _own = issued.producer);
      _syncVisible();
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProducerKeyScreen(
            controller: _controller,
            issued: issued,
            isNew: false,
            share: widget.share,
          ),
        ),
      );
      return;
    }
    if (outcome.failure == ProducerFailure.notFound) {
      setState(() => _kind = _Kind.gone);
    } else if (outcome.message('make a new key') case final message?) {
      showAppSnackBar(
        context,
        message,
        actionLabel: outcome.failure == ProducerFailure.forbidden
            ? null
            : 'Retry',
        onAction: () => _newKey(producer),
      );
    }
  }

  Future<void> _disable(OwnProducer producer) async {
    if (!await ProducerDialogs.disable(context, producer)) return;
    await _change(
      () => _ownProducers.disable(_id),
      doing: 'disable ${producer.name}',
    );
  }

  Future<void> _enable(OwnProducer producer) => _change(
    () => _ownProducers.enable(_id),
    doing: 'enable ${producer.name}',
  );

  Future<void> _removePerson(OwnProducer producer, UserName person) async {
    if (!await ProducerDialogs.removePerson(
      context,
      person: person.name,
      producer: producer,
    )) {
      return;
    }
    await _change(
      () =>
          _ownProducers.saveAllowList(_id, add: const [], remove: [person.id]),
      doing: 'remove ${person.name}',
    );
  }

  Future<void> _addPeople(OwnProducer producer) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            AllowListScreen(controller: _controller, producer: producer),
      ),
    );
    if (!mounted) return;
    setState(() => _own = _ownProducers.byId(_id) ?? _own);
  }

  void _openEvents(String name) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProducerEventsScreen(
        controller: _controller,
        producerId: _id,
        producerName: name,
      ),
    ),
  );

  /// The muted row opens the place where pushes are muted: Settings, with
  /// Push filters open.
  void _openPushFilters() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _controller.selectTab(HomeTab.settings);
    unawaited(
      _controller.setSettingsGroupOpen(SettingsGroup.pushFilters, open: true),
    );
  }

  void _backToProducers() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _controller.selectTab(HomeTab.producers);
  }

  bool get _mutedHere =>
      _controller.registration?.pushPreferences?.mutedProducerIds.contains(
        _id,
      ) ??
      false;

  // -- building --------------------------------------------------------

  @override
  Widget build(BuildContext context) => switch (_kind) {
    _Kind.loading => Scaffold(appBar: AppBar(), body: const SkeletonRows()),
    _Kind.gone => Scaffold(
      appBar: AppBar(title: const Text('Producer')),
      body: EmptyState(
        icon: Icons.sensors_off,
        title: "This producer isn't available\nany more",
        body: "It may have been made private. It's gone from your list too.",
        actionLabel: 'Back to Producers',
        onAction: _backToProducers,
      ),
    ),
    _Kind.failed => Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        icon: Icons.cloud_off,
        title: "Couldn't load this producer",
        body: _failure == ProducerFailure.server
            ? 'SignalHub had a problem. Try again in a moment.'
            : 'Check your connection and try again.',
        actionLabel: 'Try again',
        actionIcon: Icons.refresh,
        onAction: _retry,
      ),
    ),
    _Kind.own => _ownScreen(_own!),
    _Kind.other => _otherScreen(_other!),
  };

  Widget? _staleBanner() {
    if (_staleBecause == null) return null;
    final at = _loadedAt == null ? '' : ' at ${whenLabel(_loadedAt!)}';
    final offline = _staleBecause == ProducerFailure.offline;
    return AppBanner(
      icon: Icons.cloud_off,
      message: offline
          ? "You're offline. This is how it was$at. Changes are paused until "
                "you're back."
          : "Couldn't refresh. This is how it was$at.",
      actionLabel: 'Try again',
      onAction: _refresh,
    );
  }

  Widget _ownScreen(OwnProducer producer) => Scaffold(
    appBar: AppBar(
      title: Text(producer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Rename ${producer.name}',
          icon: const Icon(Icons.edit),
          onPressed: _paused || _busy ? null : () => _rename(producer),
        ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ContentWidth(
          child: OwnProducerView(
            producer: producer,
            stale: _staleBanner(),
            writable: !_paused,
            busy: _busy,
            visibility: _pendingVisibility ?? producer.visibility,
            mutedHere: _mutedHere,
            onSubscribed: (on) => _setSubscribed(on, producer.name),
            onVisibility: (v) => _setVisibility(producer, v),
            onRemovePerson: (p) => _removePerson(producer, p),
            onAddPeople: () => _addPeople(producer),
            onRevoke: (key) => _revokeKey(producer, key),
            onNewKey: () => _newKey(producer),
            onEvents: () => _openEvents(producer.name),
            onDisable: () => _disable(producer),
            onEnable: () => _enable(producer),
            onMuted: _openPushFilters,
          ),
        ),
      ),
    ),
  );

  Widget _otherScreen(VisibleProducer producer) => Scaffold(
    appBar: AppBar(
      title: Text(producer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ContentWidth(
          child: OtherProducerView(
            producer: producer,
            stale: _staleBanner(),
            writable: !_paused && !_busy,
            mutedHere: _mutedHere,
            onSubscribed: (on) => _setSubscribed(on, producer.name),
            onEvents: () => _openEvents(producer.name),
            onMuted: _openPushFilters,
          ),
        ),
      ),
    ),
  );
}
