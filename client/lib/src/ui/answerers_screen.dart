import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/own_producers_controller.dart';
import '../models/producers.dart';
import '../models/users.dart';
import 'producer_dialogs.dart';
import 'widgets/empty_state.dart';
import 'widgets/producer_parts.dart';
import 'widgets/skeleton.dart';
import 'widgets/snack.dart';

/// _Add people who can answer_: the people who can see the producer and are
/// not its answerers yet, by name, with nothing checked. It only adds:
/// removing is the close button of an answerer's row, confirmed there. _Add_
/// stays off until someone is checked. They also need to be subscribed to
/// get the questions, which the owner cannot see, so the screen says so.
class AnswerersScreen extends StatefulWidget {
  const AnswerersScreen({
    super.key,
    required this.controller,
    required this.producer,
  });

  final AppController controller;
  final OwnProducer producer;

  @override
  State<AnswerersScreen> createState() => _AnswerersScreenState();
}

class _AnswerersScreenState extends State<AnswerersScreen> {
  final _checked = <String>{};
  List<Person>? _people;
  ProducerFailure? _loadFailure;
  bool _saving = false;

  OwnProducersController get _own => widget.controller.ownProducers;

  @override
  void initState() {
    super.initState();
    _loadPeople();
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

  /// Who can see the producer: everyone while it is public, the people on its
  /// list while it is private. The owner is not listed: they always answer.
  List<UserName> get _canSee {
    final producer = widget.producer;
    final people = [
      if (producer.visibility == ProducerVisibility.public)
        for (final p in _people ?? const <Person>[])
          UserName(id: p.id, name: p.name)
      else
        ...producer.allowedUsers,
    ];
    return people
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// The people who can see it and cannot answer yet.
  List<UserName> get _candidates {
    final named = {for (final u in widget.producer.answerers) u.id};
    return [
      for (final u in _canSee)
        if (!named.contains(u.id)) u,
    ];
  }

  Future<void> _add() async {
    if (_checked.isEmpty || _saving) return;
    setState(() => _saving = true);
    final outcome = await _own.addAnswerers(
      widget.producer.id,
      _checked.toList(),
    );
    if (!mounted) return;
    if (outcome.ok) {
      Navigator.of(context).pop(outcome.value);
      return;
    }
    setState(() => _saving = false);
    if (outcome.failure == ProducerFailure.notFound ||
        outcome.failure == ProducerFailure.signedOut) {
      Navigator.of(context).pop();
      return;
    }
    showAppSnackBar(
      context,
      outcome.message('add them') ?? "Couldn't add them. Try again.",
      actionLabel: outcome.failure == ProducerFailure.forbidden
          ? null
          : 'Retry',
      onAction: _add,
    );
  }

  Future<void> _leave() async {
    if (_checked.isEmpty || await ProducerDialogs.discardAnswerers(context)) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading =
        widget.producer.visibility == ProducerVisibility.public &&
        _people == null &&
        _loadFailure == null;
    return PopScope(
      canPop: _checked.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
          title: const Text('Add people who can answer'),
        ),
        body: SafeArea(
          top: false,
          bottom: false,
          child: ContentWidth(child: _body(loading)),
        ),
        bottomNavigationBar: SafeArea(
          child: ContentWidth(
            bar: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    key: const Key('addAnswerers'),
                    onPressed: _checked.isNotEmpty && !_saving ? _add : null,
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(bool loading) {
    if (loading) return const SkeletonRows();
    final name = widget.producer.name;
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
    final candidates = _candidates;
    if (candidates.isEmpty) {
      final nobody = _canSee.isEmpty;
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          nobody
              ? 'Nobody else can see $name. Add people under Who can see it '
                    'first.'
              : 'Everyone who can see $name can already answer.',
          key: const Key('noCandidates'),
          style: Theme.of(context).textTheme.bodyLarge
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        Hint(
          'Only people who can see $name are listed. They also need to be '
          'subscribed to get its questions.',
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        ),
        for (final user in candidates)
          CheckboxListTile(
            key: Key('candidate-${user.id}'),
            value: _checked.contains(user.id),
            onChanged: _saving
                ? null
                : (on) => setState(() {
                    on == true
                        ? _checked.add(user.id)
                        : _checked.remove(user.id);
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
