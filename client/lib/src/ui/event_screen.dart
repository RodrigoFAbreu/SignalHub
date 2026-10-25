import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/signalhub_api.dart';
import '../features/answer_outcome.dart';
import '../models/event.dart';
import '../models/question.dart';
import 'answer_card.dart';
import 'event_style.dart';
import 'link_opener.dart';
import 'widgets/empty_state.dart';
import 'widgets/snack.dart';

/// One event with every field the API returns. Opened from the inbox with
/// the event at hand, or from a notification with only its ID.
///
/// Opening it marks the event read; if that fails, a message says so and the
/// event stays shown as unread. Its one read-state action, labelled, follows
/// the event's state as the server last returned it: *Mark as read* while it
/// is unread, *Mark as unread* once it is read.
///
/// An event the server can no longer read (deleted, or its producer
/// unsubscribed from) is not an error: the screen says it is not in the inbox
/// any more and goes back to it.
///
/// An event with a link offers *Open link*, which hands it to the system
/// browser; a link that cannot be opened is reported here.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.load,
    this.initial,
    this.markOpened,
    this.setRead,
    required this.openLink,
    this.myUserId,
    this.answer,
    this.reload,
    this.questionEnded,
    this.now = DateTime.now,
  });

  /// Reads the event, from the inbox or the server.
  final Future<Event> Function() load;

  /// The event, when the caller already has it.
  final Event? initial;

  /// Marks the event read when the screen opens; returns the event as the
  /// server returned it, or an error message.
  final Future<({Event? event, String? error})> Function()? markOpened;

  /// Marks the event read or unread; returns the event as the server
  /// returned it, or an error message.
  final Future<({Event? event, String? error})> Function(bool read)? setRead;

  /// Opens the event's link outside the app.
  final LinkOpener openLink;

  /// Who is looking, so an answer of theirs reads _You answered_.
  final String? myUserId;

  /// Sends an answer to the event's question; without it the card cannot
  /// send.
  final Future<AnswerOutcome> Function(List<String> choices, String? text)?
  answer;

  /// Reads the event from the server again, for a question that may have
  /// been answered or closed meanwhile.
  final Future<Event> Function()? reload;

  /// Each notice, while the app is open, that the event's question was
  /// answered or closed, or the event deleted: the card reads it again.
  final Stream<void>? questionEnded;

  /// The clock, for a question's closing time; tests replace it.
  final DateTime Function() now;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> with WidgetsBindingObserver {
  Event? _event;
  String? _error;
  bool _changing = false;

  /// Whether the server says the event is not in this user's inbox any more.
  bool _gone = false;

  /// Whether the owner changed the read state here; marking read on opening
  /// then answers with older state.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _event = widget.initial;
    if (_event == null) _load();
    if (widget.markOpened case final markOpened?) _markOpened(markOpened);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A card left open goes stale: the app reads the event again when it
  /// returns to the foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refresh());
  }

  /// Reads the event again; the screen follows only when its question or
  /// what this person may do changed, so what is typed is never disturbed.
  Future<void> _refresh() async {
    final reload = widget.reload;
    final current = _event;
    if (reload == null || current?.ask == null || _gone) return;
    try {
      final fresh = await reload();
      if (mounted) _follow(fresh);
    } on EventNotFoundException {
      if (mounted) setState(() => _gone = true);
    } on ApiException {
      // The card keeps what it shows; the next read tries again.
    }
  }

  void _follow(Event fresh) {
    final current = _event;
    if (current == null || _sameQuestion(current, fresh)) {
      // Read state is the server's too.
      if (current != null && current.readAt != fresh.readAt) {
        setState(() => _event = fresh);
      }
      return;
    }
    setState(() => _event = fresh);
  }

  static bool _sameQuestion(Event a, Event b) =>
      a.answerState == b.answerState &&
      a.canAnswer == b.canAnswer &&
      a.answer?.at == b.answer?.at &&
      a.closedBy == b.closedBy &&
      a.ask?.closesAt == b.ask?.closesAt &&
      a.ask?.whoCanAnswer.length == b.ask?.whoCanAnswer.length;

  /// A new state of the question, from the answer or a `409`: shown at once,
  /// and read again, so what the server says now replaces what was inferred.
  void _questionState(QuestionState state) {
    final current = _event;
    if (current == null) return;
    setState(() => _event = current.withQuestionState(state));
    unawaited(_refresh());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final event = await widget.load();
      // Marking read on opening may have answered first, with newer state.
      if (mounted) setState(() => _event ??= event);
    } on EventNotFoundException {
      if (mounted) setState(() => _gone = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Whether [error], from marking the event, says it is gone; the inbox has
  /// dropped it already.
  bool _saysGone(String? error) {
    if (error != const EventNotFoundException().message) return false;
    setState(() => _gone = true);
    return true;
  }

  Future<void> _markOpened(
    Future<({Event? event, String? error})> Function() markOpened,
  ) async {
    final (:event, :error) = await markOpened();
    if (!mounted || _changed) return;
    if (event != null) setState(() => _event = event);
    if (_saysGone(error)) return;
    if (error != null) showAppSnackBar(context, 'Not marked as read: $error');
  }

  Future<void> _setRead(
    Future<({Event? event, String? error})> Function(bool read) setRead,
    bool read,
  ) async {
    setState(() => _changing = _changed = true);
    final (:event, :error) = await setRead(read);
    if (!mounted) return;
    setState(() {
      _changing = false;
      if (event != null) _event = event;
    });
    if (_saysGone(error)) return;
    if (error != null) {
      // The newest outcome replaces an older message, such as the one about
      // marking on opening.
      showAppSnackBar(context, error);
    } else if (event != null && !read) {
      // Marked unread to come back to later: back to the inbox.
      Navigator.of(context).pop();
    }
  }

  Future<void> _openLink(Uri link) async {
    if (await widget.openLink(link) || !mounted) return;
    showAppSnackBar(context, 'Could not open the link');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Event'),
      actions: [
        if (!_gone)
          if ((_event, widget.setRead) case (final event?, final setRead?))
            event.isRead
                ? TextButton.icon(
                    key: const Key('markUnread'),
                    icon: const Icon(Icons.mark_email_unread_outlined),
                    label: const Text('Mark as unread'),
                    onPressed: _changing
                        ? null
                        : () => _setRead(setRead, false),
                  )
                : TextButton.icon(
                    key: const Key('markRead'),
                    icon: const Icon(Icons.mark_email_read_outlined),
                    label: const Text('Mark as read'),
                    onPressed: _changing ? null : () => _setRead(setRead, true),
                  ),
      ],
    ),
    body: switch ((_event, _error)) {
      _ when _gone => EmptyState(
        icon: Icons.event_busy,
        title: "This event isn't in your inbox any more",
        body:
            'You may have unsubscribed from its producer, or it was deleted. '
            'If you subscribe again, its older events come back.',
        actionLabel: 'Back to Inbox',
        onAction: () => Navigator.of(context).maybePop(),
      ),
      (final Event event, _) => _EventDetails(
        event,
        openLink: _openLink,
        card: event.ask == null || widget.answer == null
            ? null
            : AnswerCard(
                key: ValueKey('card-${event.id}'),
                event: event,
                myUserId: widget.myUserId,
                answer: widget.answer!,
                onState: _questionState,
                onRead: _follow,
                reread: _refresh,
                ended: widget.questionEnded,
                now: widget.now,
                onGone: () => setState(() => _gone = true),
              ),
      ),
      (null, final String error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('retryEvent'),
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    },
  );
}

class _EventDetails extends StatelessWidget {
  const _EventDetails(this.event, {required this.openLink, this.card});

  final Event event;
  final void Function(Uri link) openLink;

  /// The question's card, under the message and above the link.
  final Widget? card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severityColor = event.severity.color(theme.colorScheme);
    return SelectionArea(
      child: ListView(
        // Explicit padding drops the system insets a list pads by default:
        // without them, its end is hidden under the navigation bar.
        padding: const EdgeInsets.all(16) + MediaQuery.paddingOf(context),
        children: [
          Text(event.title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(event.category.icon),
                label: Text(event.category.label),
              ),
              Chip(
                avatar: Icon(Icons.priority_high, color: severityColor),
                label: Text(event.severity.label),
              ),
            ],
          ),
          if (event.message case final message?) ...[
            const SizedBox(height: 16),
            Text(message, style: theme.textTheme.bodyLarge),
          ],
          if (card != null) ...[const SizedBox(height: 16), card!],
          if (event.link case final link?) ...[
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.tonalIcon(
                key: const Key('openLink'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open link'),
                onPressed: () => openLink(link),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _Field('Producer', event.producer.name),
          if (event.context case final context?) _Field('Context', context),
          // Where the action goes, before the owner taps it.
          if (event.link case final link?) _Field('Link', link.toString()),
          if (event.occurredAt case final occurredAt?)
            _Field('Occurred', formatTimestamp(occurredAt)),
          _Field('Received', formatTimestamp(event.createdAt)),
          _Field('Read', switch (event.readAt) {
            final readAt? => formatTimestamp(readAt),
            null => 'Unread',
          }),
          _Field('Event ID', event.id),
          if (event.metadata.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Metadata', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            // Opaque producer data: shown as the producer sent it.
            Text(
              const JsonEncoder.withIndent('  ').convert(event.metadata),
              key: const Key('metadata'),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
