import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/client_registration.dart';
import '../models/event.dart';
import 'event_style.dart';

/// Which events are pushed to this installation: pause, minimum severity,
/// and muted categories and producers. Every change is saved on the server
/// at once. Events are kept in the inbox whatever is chosen here.
class PushPreferencesScreen extends StatelessWidget {
  const PushPreferencesScreen({super.key, required this.controller});

  final AppController controller;

  static const _severities = [
    EventSeverity.low,
    EventSeverity.normal,
    EventSeverity.high,
    EventSeverity.critical,
  ];

  static const _categories = [
    EventCategory.actionRequired,
    EventCategory.blocked,
    EventCategory.completed,
    EventCategory.info,
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final preferences = controller.registration?.pushPreferences;
        if (preferences == null) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'This server does not support push preferences. Update it to '
              'choose which events are pushed to this device.',
            ),
          );
        }
        return _Form(
          preferences: preferences,
          enabled: !controller.savingPushPreferences,
          producers: controller.inboxProducers,
          save: (changed) => _save(context, changed),
        );
      },
    ),
  );

  Future<void> _save(BuildContext context, PushPreferences changed) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await controller.setPushPreferences(changed);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _Form extends StatelessWidget {
  const _Form({
    required this.preferences,
    required this.enabled,
    required this.producers,
    required this.save,
  });

  final PushPreferences preferences;
  final bool enabled;
  final List<EventProducer> producers;
  final void Function(PushPreferences) save;

  @override
  Widget build(BuildContext context) {
    final p = preferences;
    final severity = EventSeverity.parse(p.minimumSeverity);
    // Muted producers that have no event in the inbox are still listed, by
    // ID, so they can be unmuted.
    final named = {for (final producer in producers) producer.id};
    final producerRows = [
      for (final producer in producers) (producer.id, producer.name),
      for (final id in p.mutedProducerIds)
        if (!named.contains(id)) (id, id),
    ];
    return ListView(
      children: [
        SwitchListTile(
          key: const Key('pushEnabled'),
          title: const Text('Push notifications'),
          subtitle: Text(
            p.enabled
                ? 'For this device only. Events are always kept in the inbox.'
                : 'Paused. Events are still kept in the inbox.',
          ),
          value: p.enabled,
          onChanged: enabled ? (on) => save(p.copyWith(enabled: on)) : null,
        ),
        const _Heading('Minimum severity'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<EventSeverity>(
            key: const Key('minimumSeverity'),
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final s in PushPreferencesScreen._severities)
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {if (severity != EventSeverity.unknown) severity},
            onSelectionChanged: enabled
                ? (selected) {
                    if (selected.isEmpty) return;
                    save(p.copyWith(minimumSeverity: selected.single.wireName));
                  }
                : null,
          ),
        ),
        const _Heading('Categories'),
        for (final category in PushPreferencesScreen._categories)
          SwitchListTile(
            key: Key('category-${category.wireName}'),
            secondary: Icon(category.icon),
            title: Text(category.label),
            value: !p.mutedCategories.contains(category.wireName),
            onChanged: enabled
                ? (on) => save(
                    p.copyWith(
                      mutedCategories: _toggle(
                        p.mutedCategories,
                        category.wireName,
                        muted: !on,
                      ),
                    ),
                  )
                : null,
          ),
        const _Heading('Producers'),
        if (producerRows.isEmpty)
          const ListTile(
            title: Text(
              'Producers appear here once their events are in the '
              'inbox.',
            ),
          ),
        for (final (id, name) in producerRows)
          SwitchListTile(
            key: Key('producer-$id'),
            title: Text(name),
            value: !p.mutedProducerIds.contains(id),
            onChanged: enabled
                ? (on) => save(
                    p.copyWith(
                      mutedProducerIds: _toggle(
                        p.mutedProducerIds,
                        id,
                        muted: !on,
                      ),
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  /// [values] without [value], or with it once when [muted].
  static List<String> _toggle(
    List<String> values,
    String value, {
    required bool muted,
  }) => [
    for (final v in values)
      if (v != value) v,
    if (muted) value,
  ];
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
