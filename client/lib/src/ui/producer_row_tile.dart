import 'package:flutter/material.dart';

import '../features/producers_controller.dart';
import 'widgets/bell_toggle.dart';
import 'widgets/tags.dart';

/// One producer in the Producers list: a neutral avatar (never one per
/// producer), the name with a `Yours` tag when it is the user's own, a
/// summary and the bell. The name takes the free width and ends in an
/// ellipsis; the tag and the bell keep their size.
class ProducerRowTile extends StatelessWidget {
  const ProducerRowTile({
    super.key,
    required this.row,
    required this.onOpen,
    this.mutedOnDevice = false,
    this.changingTo,
    this.onBell,
  });

  final ProducerRow row;

  /// Whether this device's push preferences mute the producer.
  final bool mutedOnDevice;

  /// The state a running subscription change moves to, or `null`.
  final bool? changingTo;

  final VoidCallback onOpen;

  /// Subscribes or unsubscribes; `null` greys the bell (offline).
  final VoidCallback? onBell;

  IconData get _avatar {
    if (row.disabledByYou) return Icons.pause_circle_outline;
    if (row.disabled) return Icons.block;
    return Icons.sensors;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: InkWell(
              onTap: onOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 72),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 0, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.surfaceContainerHighest,
                        foregroundColor: colors.onSurfaceVariant,
                        child: ExcludeSemantics(child: Icon(_avatar)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    row.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                ),
                                if (row.isYours) ...[
                                  const SizedBox(width: 8),
                                  const LabelTag('Yours'),
                                ],
                              ],
                            ),
                            Text(
                              row.summary(mutedOnDevice: mutedOnDevice),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: row.disabledByHost
                                    ? colors.error
                                    : colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Center(
              child: BellToggle(
                name: row.name,
                subscribed: row.subscribed,
                changingTo: changingTo,
                onPressed: onBell,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
