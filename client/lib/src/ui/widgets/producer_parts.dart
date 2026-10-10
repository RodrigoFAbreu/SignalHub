import 'package:flutter/material.dart';

import '../../models/users.dart';

/// One plain sentence in a container of its own, for what a screen must say
/// beside its controls: the key's one warning, a producer with no working
/// key, a producer paused by its owner. [error] is for something only the
/// host can undo (errorContainer); otherwise the container is a low surface.
class NoticeBox extends StatelessWidget {
  const NoticeBox({
    super.key,
    required this.icon,
    required this.message,
    this.error = false,
  });

  final IconData icon;
  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = error ? colors.onErrorContainer : colors.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 24,
            color: error ? colors.onErrorContainer : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a full screen's content is at most as wide as, centred: landscape
/// keeps the portrait layout.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: child,
    ),
  );
}

/// The top of a screen whose title is a name or a sentence that must stay
/// whole: the title wraps instead of ending in an ellipsis, so the bar grows
/// with the text size. A 48 dp [leading] button sits 4 dp from the edge.
class WrappingHeader extends StatelessWidget {
  const WrappingHeader({super.key, required this.leading, required this.title});

  final Widget leading;
  final String title;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 64),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A section's label: titleSmall in the primary colour.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 4),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

/// A row of a producer's screen: a 24 dp icon, a title, up to two lines
/// under it and what trails. At least 56 dp high, 16 dp from the leading edge
/// and 24 from the trailing one; the whole row is the target when it has an
/// [onTap]. The text grows with the system text size and never clips.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
    this.lines = const [],
    this.monoTitle = false,
    this.trailing,
    this.onTap,
    this.quiet = false,
    this.minHeight = 56,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final bool monoTitle;
  final List<String> lines;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Shown dimmed: a key that was revoked, an action that is not available.
  final bool quiet;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 24, 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: iconColor ?? colors.onSurfaceVariant),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: monoTitle
                        ? theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 14,
                          )
                        : theme.textTheme.bodyLarge,
                  ),
                  for (final line in lines)
                    Text(
                      line,
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
    final content = Opacity(opacity: quiet ? 0.55 : 1, child: row);
    if (onTap == null) return content;
    return InkWell(onTap: onTap, child: content);
  }
}

/// A person's initial in a circle of the tertiary container: the owner of a
/// producer, someone it is shared with. Never one per producer.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar(
    this.name, {
    super.key,
    this.size = 40,
    this.neutral = false,
  });

  final String name;
  final double size;

  /// The neutral surface of a person in a list, instead of the tertiary one.
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: neutral
              ? colors.surfaceContainerHighest
              : colors.tertiaryContainer,
          shape: BoxShape.circle,
        ),
        child: Text(
          name.isEmpty ? '' : name.characters.first.toUpperCase(),
          style:
              (size >= 40
                      ? Theme.of(context).textTheme.titleMedium
                      : Theme.of(context).textTheme.labelMedium)
                  ?.copyWith(
                    color: neutral
                        ? colors.onSurfaceVariant
                        : colors.onTertiaryContainer,
                  ),
        ),
      ),
    );
  }
}

/// The _Subscribed_ row of a producer's screen: a bell, what subscribing
/// means in a sentence and a switch. It is the same control as the bell on
/// the list, with the same words: _Subscribed_ for the state and _Subscribe_
/// for the action. The whole row is the target.
class SubscribedRow extends StatelessWidget {
  const SubscribedRow({
    super.key,
    required this.subscribed,
    required this.description,
    required this.onChanged,
  });

  final bool subscribed;
  final String description;

  /// `null` while a change is in flight or writing is paused.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: subscribed ? 'Subscribed' : 'Subscribe',
      hint: description,
      toggled: subscribed,
      onTap: onChanged == null ? null : () => onChanged!(!subscribed),
      child: DetailRow(
        icon: subscribed
            ? Icons.notifications_active
            : Icons.notifications_none,
        iconColor: subscribed ? colors.primary : null,
        title: 'Subscribed',
        lines: [description],
        trailing: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Switch(value: subscribed, onChanged: onChanged),
        ),
        onTap: onChanged == null ? null : () => onChanged!(!subscribed),
      ),
    );
  }
}

/// A one-line sentence under a control, on the body text colour.
class Hint extends StatelessWidget {
  const Hint(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 0),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// Who can see a producer: _Private_ or _Public_, as one segmented control
/// across the width. The state is spoken ("Private, selected").
class VisibilityControl extends StatelessWidget {
  const VisibilityControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ProducerVisibility value;

  /// `null` while a change is in flight or writing is paused.
  final ValueChanged<ProducerVisibility>? onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<ProducerVisibility>(
    segments: const [
      ButtonSegment(
        value: ProducerVisibility.private,
        icon: Icon(Icons.lock_outline),
        label: Text('Private'),
      ),
      ButtonSegment(
        value: ProducerVisibility.public,
        icon: Icon(Icons.public),
        label: Text('Public'),
      ),
    ],
    selected: {value},
    showSelectedIcon: false,
    expandedInsets: EdgeInsets.zero,
    onSelectionChanged: onChanged == null
        ? null
        : (selection) => onChanged!(selection.single),
  );
}
