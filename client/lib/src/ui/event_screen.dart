import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/signalhub_api.dart';
import '../models/event.dart';
import 'event_style.dart';

/// One event with every field the API returns. Opened from the inbox with
/// the event at hand, or from a notification with only its ID.
class EventScreen extends StatefulWidget {
  const EventScreen({
    super.key,
    required this.load,
    this.initial,
    this.markUnread,
  });

  /// Reads the event, from the inbox or the server.
  final Future<Event> Function() load;

  /// The event, when the caller already has it.
  final Event? initial;

  /// Marks the event unread again; returns an error message, or `null` on
  /// success, which closes the screen.
  final Future<String?> Function()? markUnread;

  @override
  State<EventScreen> createState() => _EventScreenState();
}

class _EventScreenState extends State<EventScreen> {
  Event? _event;
  String? _error;

  @override
  void initState() {
    super.initState();
    _event = widget.initial;
    if (_event == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final event = await widget.load();
      if (mounted) setState(() => _event = event);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _markUnread(Future<String?> Function() markUnread) async {
    final error = await markUnread();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Event'),
      actions: [
        if ((_event, widget.markUnread) case (_?, final markUnread?))
          IconButton(
            key: const Key('markUnread'),
            tooltip: 'Mark as unread',
            icon: const Icon(Icons.mark_email_unread_outlined),
            onPressed: () => _markUnread(markUnread),
          ),
      ],
    ),
    body: switch ((_event, _error)) {
      (final Event event, _) => _EventDetails(event),
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
  const _EventDetails(this.event);

  final Event event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final severityColor = event.severity.color(theme.colorScheme);
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 16),
          _Field('Producer', event.producer.name),
          if (event.context case final context?) _Field('Context', context),
          if (event.occurredAt case final occurredAt?)
            _Field('Occurred', formatTimestamp(occurredAt)),
          _Field('Received', formatTimestamp(event.createdAt)),
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
