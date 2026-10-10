import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A button that copies [text] and turns to _Copied_ with a check, a 120 ms
/// cross-fade with its width held. It reverts after [revertAfter] (2 seconds
/// everywhere but the key screen, which passes `null`: _Copied_ stays while
/// the screen is open). If the clipboard is refused, [onRefused] runs and the
/// button stays as it was.
class CopyButton extends StatefulWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.label = 'Copy',
    this.revertAfter = const Duration(seconds: 2),
    this.filled = false,
    this.onCopied,
    this.onRefused,
  });

  final String text;
  final String label;
  final Duration? revertAfter;
  final bool filled;
  final VoidCallback? onCopied;
  final VoidCallback? onRefused;

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _revert;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.text));
    } on PlatformException {
      widget.onRefused?.call();
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    widget.onCopied?.call();
    _revert?.cancel();
    if (widget.revertAfter case final after?) {
      _revert = Timer(after, () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Both labels are laid out, so the width never changes.
    final label = Stack(
      alignment: Alignment.center,
      children: [
        for (final (text, icon, shown) in [
          (widget.label, Icons.copy, !_copied),
          ('Copied', Icons.check, _copied),
        ])
          AnimatedOpacity(
            duration: const Duration(milliseconds: 120),
            opacity: shown ? 1 : 0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Text(text),
              ],
            ),
          ),
      ],
    );
    return Semantics(
      button: true,
      label: _copied ? 'Copied' : widget.label,
      excludeSemantics: true,
      onTap: _copy,
      child: widget.filled
          ? FilledButton.tonal(onPressed: _copy, child: label)
          : OutlinedButton(onPressed: _copy, child: label),
    );
  }
}
