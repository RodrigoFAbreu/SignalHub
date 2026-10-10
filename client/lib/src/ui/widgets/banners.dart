import 'package:flutter/material.dart';

/// A banner under the app bar and above the list. It is inline: it pushes
/// the list down and never covers it. Radius 12, at least 56 dp high, a 24 dp
/// icon and an action 48 dp high.
///
/// [error] is for something that stopped and has a next step (errorContainer
/// and onErrorContainer); otherwise it is neutral (surfaceContainerHigh and
/// onSurface), for being offline or showing an older list, which are nobody's
/// fault.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.icon,
    required this.message,
    this.error = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final bool error;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final background = error
        ? colors.errorContainer
        : colors.surfaceContainerHigh;
    final foreground = error ? colors.onErrorContainer : colors.onSurface;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 24, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: foreground),
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: error ? foreground : colors.primary,
                minimumSize: const Size(48, 48),
              ),
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}
