import 'package:flutter/material.dart';

import '../models/producers.dart';
import '../models/users.dart';
import 'widgets/producer_parts.dart';

/// What a producer's screen shows for one somebody else owns: who owns it and
/// who can see it, and the subscription, which is this user's alone. There
/// are no keys, no allow-list and no way to change the producer.
class OtherProducerView extends StatelessWidget {
  const OtherProducerView({
    super.key,
    required this.producer,
    required this.stale,
    required this.writable,
    required this.mutedHere,
    required this.onSubscribed,
    required this.onEvents,
    required this.onMuted,
  });

  final VisibleProducer producer;

  /// The banner that says the screen shows an older state, if it does.
  final Widget? stale;
  final bool writable;
  final bool mutedHere;
  final ValueChanged<bool> onSubscribed;
  final VoidCallback onEvents;
  final VoidCallback onMuted;

  @override
  Widget build(BuildContext context) {
    final owner = producer.owner.name;
    final isPublic = producer.visibility == ProducerVisibility.public;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ?stale,
        if (producer.disabled)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: NoticeBox(
              icon: Icons.pause_circle_outline,
              message: "Disabled. It isn't sending events.",
            ),
          ),
        _OwnerRow(
          owner: owner,
          title: isPublic ? "$owner's producer" : '$owner added you',
          subtitle: isPublic
              ? 'Public · anyone on this server can subscribe'
              : 'Private · only $owner and the people $owner added can see it',
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1),
        ),
        SubscribedRow(
          subscribed: producer.subscribed,
          description: producer.subscribed
              ? (mutedHere
                    ? 'Its events are in your inbox.'
                    : 'Its events are in your inbox, and pushed as your '
                          'filters allow. Turn it off and they leave your '
                          'inbox; they come back if you subscribe again.')
              : 'Subscribe to get its events in your inbox. You\'ll find its '
                    'older events too.',
          onChanged: writable ? onSubscribed : null,
        ),
        if (producer.subscribed && mutedHere)
          DetailRow(
            icon: Icons.volume_off,
            title: 'Muted on this device',
            lines: const [
              'No pushes from it here. Its events still reach your inbox.',
            ],
            trailing: const Icon(Icons.chevron_right),
            onTap: onMuted,
          ),
        if (producer.subscribed)
          DetailRow(
            icon: Icons.filter_list,
            title: 'See its events',
            trailing: const Icon(Icons.chevron_right),
            onTap: onEvents,
          ),
      ],
    );
  }
}

class _OwnerRow extends StatelessWidget {
  const _OwnerRow({
    required this.owner,
    required this.title,
    required this.subtitle,
  });

  final String owner;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
      child: Row(
        children: [
          PersonAvatar(owner),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
