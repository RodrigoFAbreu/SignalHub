import 'package:flutter/material.dart';

/// One thing the welcome or _What's new_ says: an icon, a bold lead and the
/// sentence that goes on from it.
class Fact {
  const Fact(this.icon, this.lead, this.text);

  final IconData icon;

  /// Set in bold, and part of the sentence: `Producers` then ` send events`.
  final String lead;
  final String text;
}

/// A [Fact] as a row: the icon at the top left, the text wrapping beside it.
class FactRow extends StatelessWidget {
  const FactRow(this.fact, {super.key, this.iconColor, this.textColor});

  final Fact fact;
  final Color? iconColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(color: textColor);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(fact.icon, size: 24, color: iconColor)),
        const SizedBox(width: 12),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: style,
              children: [
                TextSpan(
                  text: fact.lead,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: fact.text),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
