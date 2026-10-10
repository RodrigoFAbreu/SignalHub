import 'package:flutter/material.dart';

/// A list row as the drawings have it: at least 56 dp, a leading icon or
/// avatar, a one-line name that ends in an ellipsis while its [tags] keep
/// their size, an optional second line (two lines at most), and a trailing
/// chevron or action. [greyed] is for something that is gone but listed.
class AppRow extends StatelessWidget {
  const AppRow({
    super.key,
    required this.title,
    this.leading,
    this.tags = const [],
    this.subtitle,
    this.trailing,
    this.trailingIsAction = false,
    this.onTap,
    this.greyed = false,
  });

  final Widget? leading;
  final String title;
  final List<Widget> tags;
  final String? subtitle;
  final Widget? trailing;

  /// A trailing button already has its own 48 dp target and padding, so the
  /// row's trailing edge is 4 dp instead of 24.
  final bool trailingIsAction;
  final VoidCallback? onTap;
  final bool greyed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, trailingIsAction ? 4 : 24, 12),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 16)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      for (final tag in tags)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: tag,
                        ),
                    ],
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
    final body = onTap == null ? row : InkWell(onTap: onTap, child: row);
    return greyed ? Opacity(opacity: 0.62, child: body) : body;
  }
}

/// A section label in the primary colour (`Role`, `Devices`, `For`), with an
/// optional word beside it such as a role tag.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Flexible(
            child: Semantics(
              header: true,
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

/// The padding of a screen's own content: 16 dp at the sides and the bottom,
/// and [top], plus the system insets at the sides and the bottom. Not the top
/// inset, which the app bar already covers. Explicit, because a list that
/// pads itself by the insets would hide its end under the navigation bar.
EdgeInsets screenPadding(BuildContext context, {double top = 8}) {
  final insets = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(
    16 + insets.left,
    top,
    16 + insets.right,
    16 + insets.bottom,
  );
}
