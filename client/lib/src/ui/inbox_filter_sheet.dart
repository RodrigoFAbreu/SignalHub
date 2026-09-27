import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../models/event.dart';
import '../models/inbox_filter.dart';

/// Chooses which events the inbox shows: unread only, and producers,
/// categories and severities. Every change applies at once.
class InboxFilterSheet extends StatelessWidget {
  const InboxFilterSheet({super.key, required this.controller});

  final AppController controller;

  static final categories = [
    for (final c in EventCategory.values)
      if (c != EventCategory.unknown) c,
  ];

  static final severities = [
    for (final s in EventSeverity.values)
      if (s != EventSeverity.unknown) s,
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final filter = controller.filter;
      void apply(InboxFilter next) => controller.setFilter(next);
      final producers = controller.inboxProducers;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            ListTile(
              title: Text(
                'Show in the inbox',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              trailing: TextButton(
                key: const Key('clearFiltersInSheet'),
                onPressed: filter.isActive ? controller.clearFilter : null,
                child: const Text('Clear all'),
              ),
            ),
            SwitchListTile(
              key: const Key('unreadOnly'),
              title: const Text('Unread only'),
              value: filter.unreadOnly,
              onChanged: (value) => apply(filter.copyWith(unreadOnly: value)),
            ),
            const _Heading('Producers'),
            if (producers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Producers appear here once their events are in the '
                  'inbox.',
                ),
              ),
            _Chips([
              for (final producer in producers)
                FilterChip(
                  key: Key('filterProducer-${producer.id}'),
                  label: Text(producer.name),
                  selected: filter.producerIds.contains(producer.id),
                  onSelected: (_) => apply(
                    filter.copyWith(
                      producerIds: toggled(filter.producerIds, producer.id),
                    ),
                  ),
                ),
            ]),
            const _Heading('Categories'),
            _Chips([
              for (final category in categories)
                FilterChip(
                  key: Key('filterCategory-${category.wireName}'),
                  label: Text(category.label),
                  selected: filter.categories.contains(category),
                  onSelected: (_) => apply(
                    filter.copyWith(
                      categories: toggled(filter.categories, category),
                    ),
                  ),
                ),
            ]),
            const _Heading('Severities'),
            _Chips([
              for (final severity in severities)
                FilterChip(
                  key: Key('filterSeverity-${severity.wireName}'),
                  label: Text(severity.label),
                  selected: filter.severities.contains(severity),
                  onSelected: (_) => apply(
                    filter.copyWith(
                      severities: toggled(filter.severities, severity),
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

/// The active filters, above the inbox, and the one action that clears them.
class ActiveFilterBar extends StatelessWidget {
  const ActiveFilterBar({
    super.key,
    required this.controller,
    required this.onEdit,
  });

  final AppController controller;

  /// Opens the filters to change them.
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final filter = controller.filter;
    final names = {for (final p in controller.inboxProducers) p.id: p.name};
    final labels = [
      if (filter.unreadOnly) 'Unread',
      for (final id in filter.producerIds) names[id] ?? id,
      for (final c in InboxFilterSheet.categories)
        if (filter.categories.contains(c)) c.label,
      for (final s in InboxFilterSheet.severities)
        if (filter.severities.contains(s)) s.label,
    ];
    return Material(
      key: const Key('activeFilters'),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final label in labels)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(label: Text(label), onPressed: onEdit),
                    ),
                ],
              ),
            ),
          ),
          TextButton(
            key: const Key('clearFilters'),
            onPressed: controller.clearFilter,
            child: const Text('Clear'),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
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
