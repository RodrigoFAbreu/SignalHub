import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/own_producers_controller.dart';
import '../models/producers.dart';
import '../models/users.dart';
import 'producer_dialogs.dart';
import 'widgets/empty_state.dart';
import 'widgets/producer_parts.dart';
import 'widgets/search_field.dart';
import 'widgets/skeleton.dart';
import 'widgets/snack.dart';

/// _Who can see_ a private producer: the other people on the server by name,
/// with the ones on the list checked. Names only, as the server serves them.
/// Save stays off until the selection changes; it asks first only when it
/// takes someone off the list, and a save that fails leaves the screen and
/// the selection as they are.
class AllowListScreen extends StatefulWidget {
  const AllowListScreen({
    super.key,
    required this.controller,
    required this.producer,
  });

  final AppController controller;
  final OwnProducer producer;

  /// More people than this get a search field and a count of who is
  /// selected.
  static const searchFrom = 8;

  @override
  State<AllowListScreen> createState() => _AllowListScreenState();
}

class _AllowListScreenState extends State<AllowListScreen> {
  final _search = TextEditingController();

  /// The people who can see it as the server last said, by ID.
  late Set<String> _saved = {
    for (final u in widget.producer.allowedUsers) u.id,
  };
  late final Set<String> _selected = {..._saved};
  List<Person>? _people;
  ProducerFailure? _loadFailure;
  bool _saving = false;
  String _query = '';

  OwnProducersController get _own => widget.controller.ownProducers;

  @override
  void initState() {
    super.initState();
    _loadPeople();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadPeople() async {
    setState(() => _loadFailure = null);
    final outcome = await _own.readPeople();
    if (!mounted) return;
    setState(() {
      _people = outcome.value;
      _loadFailure = outcome.failure;
    });
  }

  /// The people shown: everyone the server lists, and anyone on the list it
  /// no longer lists, so they can still be taken off.
  List<UserName> get _everyone {
    final people = _people ?? const <Person>[];
    final listed = {for (final p in people) p.id};
    return [
      for (final p in people) UserName(id: p.id, name: p.name),
      for (final u in widget.producer.allowedUsers)
        if (!listed.contains(u.id)) u,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  String _nameOf(String id) =>
      _everyone.where((u) => u.id == id).firstOrNull?.name ?? id;

  bool get _changed =>
      _selected.length != _saved.length || !_selected.containsAll(_saved);

  Future<void> _save() async {
    if (!_changed || _saving) return;
    final added = _selected.difference(_saved).toList();
    final removed = _saved.difference(_selected).toList();
    if (removed.isNotEmpty &&
        !await ProducerDialogs.saveAllowList(
          context,
          producer: widget.producer,
          removed: [for (final id in removed) _nameOf(id)],
          added: [for (final id in added) _nameOf(id)],
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final outcome = await _own.saveAllowList(
      widget.producer.id,
      add: added,
      remove: removed,
    );
    if (!mounted) return;
    if (outcome.ok) {
      Navigator.of(context).pop(true);
      return;
    }
    // What worked before the failure is saved: the list as the controller
    // holds it is the baseline, the selection stays as it was.
    final stored = _own.byId(widget.producer.id);
    setState(() {
      _saving = false;
      if (stored != null) _saved = {for (final u in stored.allowedUsers) u.id};
    });
    if (outcome.failure == ProducerFailure.notFound ||
        outcome.failure == ProducerFailure.signedOut) {
      Navigator.of(context).pop(false);
      return;
    }
    final message = outcome.failure == ProducerFailure.forbidden
        ? outcome.message('save')
        : "Couldn't save. Your changes are still here.";
    showAppSnackBar(
      context,
      message!,
      actionLabel: outcome.failure == ProducerFailure.forbidden
          ? null
          : 'Retry',
      onAction: _save,
    );
  }

  @override
  Widget build(BuildContext context) {
    final everyone = _everyone;
    final loading = _people == null && _loadFailure == null;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Who can see ${widget.producer.name}'),
      ),
      body: SafeArea(
        top: false,
        child: ContentWidth(
          child: Column(
            children: [
              Expanded(child: _body(everyone, loading)),
              if (_people != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: const Key('saveAllowList'),
                      onPressed: _changed && !_saving ? _save : null,
                      child: const Text('Save'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(List<UserName> everyone, bool loading) {
    if (loading) return const SkeletonRows();
    if (_loadFailure != null) {
      return EmptyState(
        icon: Icons.cloud_off,
        title: "Couldn't load people",
        body: _loadFailure == ProducerFailure.server
            ? 'SignalHub had a problem. Try again in a moment.'
            : 'Check your connection and try again.',
        actionLabel: 'Try again',
        actionIcon: Icons.refresh,
        onAction: _loadPeople,
      );
    }
    if (everyone.isEmpty) {
      return const EmptyState(
        icon: Icons.group,
        title: 'Nobody else is here yet',
        body:
            "There's no one else on this server to add. An admin of this "
            'server can invite people.',
      );
    }
    final searching = everyone.length > AllowListScreen.searchFrom;
    final shown = [
      for (final u in everyone)
        if (u.name.toLowerCase().contains(_query.toLowerCase())) u,
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        if (searching)
          AppSearchField(
            controller: _search,
            hint: 'Search people',
            onChanged: (value) => setState(() => _query = value.trim()),
          )
        else
          const Hint(
            "They can find it and subscribe. You choose; they don't get a "
            'request.',
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          ),
        if (searching)
          Hint(
            '${_selected.length} selected',
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          ),
        for (final user in shown)
          CheckboxListTile(
            key: Key('person-${user.id}'),
            value: _selected.contains(user.id),
            onChanged: _saving
                ? null
                : (on) => setState(() {
                    on == true
                        ? _selected.add(user.id)
                        : _selected.remove(user.id);
                  }),
            controlAffinity: ListTileControlAffinity.trailing,
            secondary: PersonAvatar(user.name, neutral: true),
            title: Text(
              user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 24, 4),
            minVerticalPadding: 8,
          ),
      ],
    );
  }
}
