import 'package:flutter/material.dart';

enum CalloutKind {
  /// Something stopped and there is a next step (errorContainer).
  error,

  /// Something worked (primaryContainer).
  ok,

  /// A plain notice or warning (surfaceContainer).
  neutral,
}

/// A rounded box on a screen's own content: an icon beside one or two
/// sentences. Unlike an `AppBanner`, which sits under the app bar, it takes
/// the width its screen gives it. [live] announces it to screen readers when
/// it appears.
class Callout extends StatelessWidget {
  const Callout({
    super.key,
    required this.kind,
    required this.icon,
    required this.child,
    this.live = false,
  });

  /// A callout of one sentence.
  Callout.text(
    String text, {
    Key? key,
    required CalloutKind kind,
    required IconData icon,
    bool live = false,
  }) : this(key: key, kind: kind, icon: icon, live: live, child: Text(text));

  final CalloutKind kind;
  final IconData icon;
  final Widget child;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (background, foreground) = switch (kind) {
      CalloutKind.error => (colors.errorContainer, colors.onErrorContainer),
      CalloutKind.ok => (colors.primaryContainer, colors.onPrimaryContainer),
      CalloutKind.neutral => (colors.surfaceContainer, colors.onSurfaceVariant),
    };
    return Semantics(
      container: true,
      liveRegion: live,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(child: Icon(icon, color: foreground)),
            const SizedBox(width: 12),
            Expanded(
              child: DefaultTextStyle.merge(
                style: theme.textTheme.bodyMedium!.copyWith(color: foreground),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
