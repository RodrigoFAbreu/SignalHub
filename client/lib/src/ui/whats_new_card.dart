import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'widgets/fact_row.dart';

/// Shown once, at the top of the inbox, on a device that was already
/// connected when the app updated: what changed. A newly connected device
/// gets the welcome instead. _See Producers_ opens the tab and dismisses;
/// _Got it_ dismisses for good.
class WhatsNewCard extends StatelessWidget {
  const WhatsNewCard({super.key, required this.controller});

  final AppController controller;

  /// What changed, in order; People is for an admin only.
  static List<Fact> facts({required bool admin}) => [
    const Fact(
      Icons.call_to_action_outlined,
      'A bottom bar.',
      ' Inbox, Producers and Settings are one tap away.',
    ),
    const Fact(
      Icons.sensors,
      'Producers.',
      " Make your own, share them, and subscribe to others'.",
    ),
    if (admin)
      const Fact(
        Icons.group_outlined,
        'People.',
        ' Invite people and manage their devices.',
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = theme.colorScheme.onPrimaryContainer;
    final button = TextButton.styleFrom(
      foregroundColor: on,
      minimumSize: const Size(48, 48),
    );
    return Container(
      key: const Key('whatsNew'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              "What's new",
              style: theme.textTheme.titleMedium?.copyWith(color: on),
            ),
          ),
          for (final fact in facts(admin: controller.role.isAdmin))
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: FactRow(fact, iconColor: on, textColor: on),
            ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 4,
            children: [
              TextButton(
                key: const Key('whatsNewSeeProducers'),
                style: button,
                onPressed: () => controller.dismissWhatsNew(seeProducers: true),
                child: const Text('See Producers'),
              ),
              TextButton(
                key: const Key('whatsNewGotIt'),
                style: button,
                onPressed: controller.dismissWhatsNew,
                child: const Text('Got it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
