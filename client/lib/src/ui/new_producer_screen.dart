import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../features/own_producers_controller.dart';
import '../models/producer_name.dart';
import '../models/producers.dart';
import '../models/users.dart';
import 'producer_key_screen.dart';
import 'producer_name_field.dart';
import 'producer_screen.dart';
import 'text_sharer.dart';
import 'widgets/producer_parts.dart';
import 'widgets/snack.dart';

/// _New producer_: a full screen to name a producer and choose who can see
/// it, which ends on the key screen. The name is checked while it is typed,
/// and Create stays off until the server would take it. The X closes without
/// asking: nothing was made.
class NewProducerScreen extends StatefulWidget {
  const NewProducerScreen({
    super.key,
    required this.controller,
    this.share = shareText,
  });

  final AppController controller;
  final TextSharer share;

  @override
  State<NewProducerScreen> createState() => _NewProducerScreenState();
}

class _NewProducerScreenState extends State<NewProducerScreen> {
  final _name = TextEditingController();
  ProducerVisibility _visibility = ProducerVisibility.private;
  bool _busy = false;

  /// What the server said about the names it was asked, so the same name is
  /// not asked again and the field keeps saying why.
  final _refused = <String, ProducerFailure>{};

  /// Names the server called taken that turned out to be this user's own: a
  /// first try that worked, whose answer never arrived.
  final _mine = <String, OwnProducer>{};

  OwnProducersController get _own => widget.controller.ownProducers;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  OwnProducer? get _lostAnswer => _mine[_name.text];

  String? get _serverError {
    if (_lostAnswer case final mine?) {
      return 'You already have a producer called ${mine.name}.';
    }
    return switch (_refused[_name.text]) {
      ProducerFailure.taken => NameMessages.taken,
      ProducerFailure.notAllowed => NameMessages.notAllowed,
      _ => null,
    };
  }

  bool get _canCreate =>
      !_busy && ProducerName.check(_name.text) == null && _serverError == null;

  Future<void> _create() async {
    if (!_canCreate) return;
    final name = _name.text;
    setState(() => _busy = true);
    final outcome = await _own.create(name, _visibility);
    if (!mounted) return;
    final issued = outcome.value;
    if (issued != null) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ProducerKeyScreen(
            controller: widget.controller,
            issued: issued,
            share: widget.share,
          ),
        ),
      );
      return;
    }
    await _explain(name, outcome);
  }

  Future<void> _explain(String name, ProducerOutcome<Object?> outcome) async {
    final failure = outcome.failure!;
    if (failure == ProducerFailure.taken) {
      // The server does not say whose the name is: look at our own producers
      // first, since a first try whose answer was lost looks the same.
      await _own.load();
      if (!mounted) return;
      if (_own.byName(name) case final mine?) _mine[name] = mine;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (failure == ProducerFailure.taken ||
          failure == ProducerFailure.notAllowed) {
        _refused[name] = failure;
      }
    });
    if (failure == ProducerFailure.taken ||
        failure == ProducerFailure.notAllowed) {
      return;
    }
    if (outcome.message('create $name') case final message?) {
      showAppSnackBar(
        context,
        message,
        actionLabel: failure == ProducerFailure.forbidden ? null : 'Retry',
        onAction: _create,
      );
    }
  }

  void _openMine(OwnProducer mine) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProducerScreen(
          controller: widget.controller,
          producerId: mine.id,
          share: widget.share,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = _lostAnswer;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('New producer'),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ContentWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'A producer is anything that sends you events: a script, a '
                  'CI pipeline, a home server. It gets its own key.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ProducerNameField(
                  controller: _name,
                  serverError: _serverError,
                  help: NameMessages.help,
                  autofocus: true,
                  enabled: !_busy,
                  onSubmitted: _create,
                ),
                if (mine != null) ...[
                  const SizedBox(height: 16),
                  const NoticeBox(
                    icon: Icons.key_off_outlined,
                    message:
                        'Your first try probably worked, but its key never '
                        'reached this phone. Keys are shown once, so make a '
                        'new key for it.',
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonal(
                      key: const Key('openMine'),
                      onPressed: () => _openMine(mine),
                      child: Text('Open ${mine.name}'),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Who can see it',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                VisibilityControl(
                  value: _visibility,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _visibility = v),
                ),
                const SizedBox(height: 16),
                Text(
                  'Only you, and people you add later. Anyone on this server '
                  'can find and subscribe to a public producer.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // In the bottom bar, so a snackbar rests above Create and never over it.
      bottomNavigationBar: SafeArea(
        child: ContentWidth(
          bar: true,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FilledButton.icon(
                  key: const Key('create'),
                  onPressed: _canCreate ? _create : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  label: const Text('Create'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
