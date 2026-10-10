import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../models/producers.dart';
import 'producer_dialogs.dart';
import 'producer_screen.dart';
import 'text_sharer.dart';
import 'widgets/copy_button.dart';
import 'widgets/producer_parts.dart';

/// The send example under the key: a sample host and a sample key that is
/// plainly not real, never the producer's own, so what is on screen to copy by
/// mistake is harmless. It needs nothing but curl.
const sampleSendExample =
    'curl -X POST https://signalhub.example/api/v1/events \\\n'
    '  -H "Authorization: Bearer shpk1_EXAMPLEKEY-not-a-real-key-0000" \\\n'
    '  -H "Content-Type: application/json" \\\n'
    '  -d \'{"category":"INFO","severity":"NORMAL","title":"Hello"}\'';

/// A key, shown once: a full screen the person leaves on purpose, for a new
/// producer or for a new key of one that exists. Nothing keeps the key after
/// it. The close icon, system Back and predictive back all go through one
/// guard that asks once, and only when the key was neither copied nor shared.
class ProducerKeyScreen extends StatefulWidget {
  const ProducerKeyScreen({
    super.key,
    required this.controller,
    required this.issued,
    this.isNew = true,
    this.share = shareText,
  });

  final AppController controller;
  final IssuedProducerKey issued;

  /// Whether the producer was just made: leaving then goes to its screen,
  /// which the key screen replaces. Otherwise it goes back to the screen that
  /// made the key.
  final bool isNew;
  final TextSharer share;

  @override
  State<ProducerKeyScreen> createState() => _ProducerKeyScreenState();
}

class _ProducerKeyScreenState extends State<ProducerKeyScreen> {
  late final _key = TextEditingController(text: widget.issued.apiKey);
  final _keyFocus = FocusNode();
  bool _copied = false;
  bool _shared = false;
  bool _clipboardRefused = false;

  String get _name => widget.issued.producer.name;

  /// Copying, sharing and Copy and close all count: the key is out of the
  /// app.
  bool get _kept => _copied || _shared;

  @override
  void dispose() {
    _key.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  void _selectKey() {
    _keyFocus.requestFocus();
    _key.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _key.text.length,
    );
  }

  /// The clipboard said no: the key shows as selected, so the person can copy
  /// it by hand.
  void _refuse() {
    _selectKey();
    setState(() => _clipboardRefused = true);
  }

  Future<void> _share() async {
    if (await widget.share(widget.issued.apiKey) && mounted) {
      setState(() => _shared = true);
    }
  }

  Future<void> _copyAndClose() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.issued.apiKey));
    } on PlatformException {
      if (mounted) _refuse();
      return;
    }
    if (mounted) _close();
  }

  Future<void> _leave() async {
    if (!_kept &&
        !await ProducerDialogs.leaveWithoutKey(context, producerName: _name)) {
      return;
    }
    if (mounted) _close();
  }

  void _close() {
    final navigator = Navigator.of(context);
    if (!widget.isNew) {
      navigator.pop();
      return;
    }
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ProducerScreen(
          controller: widget.controller,
          producerId: widget.issued.producer.id,
          share: widget.share,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        body: SafeArea(
          child: ContentWidth(
            child: Column(
              children: [
                WrappingHeader(
                  leading: IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: _leave,
                  ),
                  title: widget.isNew
                      ? '$_name is ready'
                      : 'New key for $_name',
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          widget.isNew
                              ? 'This is its key. Put it where the producer '
                                    'runs; it sends events with it.'
                              : 'This is its new key. Switch the producer to '
                                    'it, then revoke the old one.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 16),
                        _KeyBox(
                          controller: _key,
                          focusNode: _keyFocus,
                          onTap: _selectKey,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            CopyButton(
                              text: widget.issued.apiKey,
                              filled: true,
                              revertAfter: null,
                              onCopied: () => setState(() {
                                _copied = true;
                                _clipboardRefused = false;
                              }),
                              onRefused: _refuse,
                            ),
                            OutlinedButton.icon(
                              onPressed: _share,
                              icon: const Icon(Icons.share, size: 18),
                              label: const Text('Share'),
                            ),
                          ],
                        ),
                        if (_clipboardRefused) ...[
                          const SizedBox(height: 16),
                          Text(
                            key: const Key('copyByHand'),
                            "Couldn't copy it. Touch and hold the key, then "
                            'choose Copy.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        NoticeBox(
                          icon: Icons.visibility_off,
                          message: widget.isNew
                              ? "Shown once. You won't see this key again. If "
                                    'you lose it, make a new key on the '
                                    "producer's screen."
                              : "Shown once. You won't see this key again. If "
                                    'you lose it, make another new key.',
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'To send a test event',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            sampleSendExample,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 18 / 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      key: const Key('copyAndClose'),
                      onPressed: _copied ? _close : _copyAndClose,
                      icon: _copied ? null : const Icon(Icons.copy, size: 18),
                      label: Text(_copied ? 'Done' : 'Copy and close'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The key in monospace on a container one step above the surface. It wraps
/// at any character, so all of it is always in view, and a tap selects all of
/// it for a copy by hand.
class _KeyBox extends StatelessWidget {
  const _KeyBox({
    required this.controller,
    required this.focusNode,
    required this.onTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Key',
      child: TextField(
        key: const Key('apiKey'),
        controller: controller,
        focusNode: focusNode,
        readOnly: true,
        showCursor: false,
        maxLines: null,
        onTap: onTap,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          height: 22 / 14,
        ),
        decoration: InputDecoration(
          filled: true,
          fillColor: colors.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}
