import 'package:flutter/material.dart';

import '../../models/users.dart';

/// A role as a word in a 24 dp pill, never an icon or a colour alone:
/// filled for an admin, tonal for a mod, outlined for a basic user. No role
/// tag is ever red.
class RoleTag extends StatelessWidget {
  const RoleTag(this.role, {super.key});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, border) = switch (role) {
      UserRole.admin => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        null,
      ),
      UserRole.mod => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        null,
      ),
      UserRole.basic => (
        Colors.transparent,
        colors.onSurfaceVariant,
        colors.outline,
      ),
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(
        role.label,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}

/// How a [LabelTag] looks: neutral (`Yours`, `Browser`, `Revoked`) or
/// primary (`You`, `This device`, `This browser`, `Admin device`).
enum LabelTagStyle { neutral, primary }

/// A 20 dp tag with a 6 dp corner beside a name: `Yours`, `You`,
/// `Admin device`, `Browser`, `This device`, `This browser`, `Revoked`. The
/// app and the web page use these words and no others.
class LabelTag extends StatelessWidget {
  const LabelTag(this.label, {super.key, this.style = LabelTagStyle.neutral});

  final String label;
  final LabelTagStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (style) {
      LabelTagStyle.neutral => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
      ),
      LabelTagStyle.primary => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
    };
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: foreground),
      ),
    );
  }
}
