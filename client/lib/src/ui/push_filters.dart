import 'package:flutter/material.dart';

import '../models/client_registration.dart';
import '../models/event.dart';
import 'event_style.dart';

/// The _Push notifications_ switch: whether events are pushed to this
/// installation at all, saved on the server. Events are kept in the inbox
/// either way.
class PushSwitch extends StatelessWidget {
  const PushSwitch({
    super.key,
    required this.preferences,
    required this.enabled,
    required this.save,
  });

  final PushPreferences preferences;
  final bool enabled;
  final void Function(PushPreferences) save;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    key: const Key('pushEnabled'),
    title: const Text('Push notifications'),
    subtitle: Text(
      preferences.enabled
          ? 'For this device only. Events are always kept in the inbox.'
          : 'Paused. Events are still kept in the inbox.',
    ),
    value: preferences.enabled,
    onChanged: enabled ? (on) => save(preferences.copyWith(enabled: on)) : null,
  );
}

/// Which events are pushed to this installation: minimum severity, and
/// muted categories and producers, saved on the server at every change.
class PushFilters extends StatelessWidget {
  const PushFilters({
    super.key,
    required this.preferences,
    required this.enabled,
    required this.producers,
    required this.save,
  });

  final PushPreferences preferences;
  final bool enabled;
  final List<EventProducer> producers;
  final void Function(PushPreferences) save;

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

  /// One line for the folded group, such as _Normal and up · Info muted ·
  /// all producers_.
  static String summary(
    PushPreferences preferences,
    List<EventProducer> producers,
  ) {
    final severity = switch (EventSeverity.parse(preferences.minimumSeverity)) {
      EventSeverity.low || EventSeverity.unknown => 'All severities',
      EventSeverity.critical => 'Critical only',
      final s => '${s.label} and up',
    };
    final muted = preferences.mutedCategories.toSet();
    final categories = [
      for (final c in _categories)
        if (muted.contains(c.wireName)) c.label,
    ];
    final names = {for (final p in producers) p.id: p.name};
    final mutedProducers = [
      for (final id in preferences.mutedProducerIds) names[id] ?? id,
    ];
    return [
      severity,
      categories.isEmpty ? 'all categories' : '${categories.join(', ')} muted',
      if (mutedProducers.isEmpty)
        'all producers'
      else if (mutedProducers.length <= 2)
        '${mutedProducers.join(', ')} muted'
      else
        '${mutedProducers.length} producers muted',
    ].join(' · ');
  }

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Heading('Minimum severity'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<EventSeverity>(
            key: const Key('minimumSeverity'),
            showSelectedIcon: false,
            emptySelectionAllowed: true,
            segments: [
              for (final s in _severities)
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
        for (final category in _categories)
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
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
