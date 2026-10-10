import 'package:flutter/material.dart';

/// A filled button for a main action that takes a moment: while [busy] it
/// keeps its label, shows a small spinner in its icon slot and ignores taps.
/// With [onPressed] `null` it is off, as a form is that is not valid yet.
class BusyFilledButton extends StatelessWidget {
  const BusyFilledButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onPressed == null ? null : (busy ? () {} : onPressed),
    icon: busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : (icon == null ? null : Icon(icon, size: 18)),
    label: Text(label),
  );
}
