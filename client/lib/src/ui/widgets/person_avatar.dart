import 'package:flutter/material.dart';

/// A person's neutral avatar: their initial on a tonal circle, never a
/// picture. Your own is primary-toned.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar(this.name, {super.key, this.you = false, this.size = 40});

  final String name;
  final bool you;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? ''
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: you ? colors.primaryContainer : colors.tertiaryContainer,
        ),
        child: Text(
          initial,
          // The avatar keeps its size, so its letter does not grow with the
          // text size.
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: size >= 40 ? 16 : 14,
            fontWeight: FontWeight.w500,
            color: you ? colors.onPrimaryContainer : colors.onTertiaryContainer,
          ),
        ),
      ),
    );
  }
}
