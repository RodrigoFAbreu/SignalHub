import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../features/pairing_code_controller.dart';
import 'widgets/app_row.dart';
import 'widgets/callout.dart';
import 'widgets/copy_button.dart';
import 'widgets/pairing_qr.dart';
import 'widgets/share_text.dart';
import 'widgets/snack.dart';

/// The pairing code screen an invitation and _Connect a device_ share: the
/// code as a QR code with its countdown and as a link to copy or share, a
/// warning that names who it is for, and, once the code is used or runs out,
/// that instead of the countdown. While a code is shown it asks now and then
/// whether a device used it, and only while the screen is open and the app is
/// in the foreground.
///
/// The words differ per screen, so they are given: [intro] opens the screen,
/// [countdownLead] begins the line the time left ends, [warning] says whose
/// device the code gives, [joined] says who used it, [ranOut] says it ended.
class PairingCodeView extends StatefulWidget {
  const PairingCodeView({
    super.key,
    required this.controller,
    required this.intro,
    required this.countdownLead,
    required this.warning,
    required this.joined,
    required this.ranOut,
    required this.onNewCode,
    required this.onDone,
    this.ranOutNote,
    this.centerNewCode = false,
  });

  /// How often the screen asks whether the code shown was used, as the
  /// admin page does.
  static const pollInterval = Duration(milliseconds: 2500);

  final PairingCodeController controller;
  final InlineSpan intro;
  final String countdownLead;
  final String warning;

  /// What it says once a device used the code, given that device's name.
  final InlineSpan Function(String deviceName) joined;
  final String ranOut;

  /// A line under _Make a new code_.
  final String? ranOutNote;
  final VoidCallback onNewCode;
  final VoidCallback onDone;
  final bool centerNewCode;

  @override
  State<PairingCodeView> createState() => _PairingCodeViewState();
}

class _PairingCodeViewState extends State<PairingCodeView> {
  PairingCodeController get _code => widget.controller;

  late final Timer _ticker;
  late final Timer _poller;

  /// The code the countdown was last announced for at one minute left, and
  /// at its end, so each is said once per code.
  Object? _minuteAnnouncedFor;
  Object? _endAnnouncedFor;

  /// The code asked about once more as it ran out, so it is asked once.
  Object? _askedAtEnd;

  @override
  void initState() {
    super.initState();
    // Redraws the countdown; nothing to do while no code is shown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Asks only while an unexpired code is shown; the screen stops asking
    // when it is left.
    _poller = Timer.periodic(PairingCodeView.pollInterval, (_) {
      if (_code.pairing != null && !_code.isExpired) unawaited(_check());
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _poller.cancel();
    super.dispose();
  }

  void _tick() {
    final pairing = _code.pairing;
    if (pairing == null || _code.isUsed || !mounted) return;
    setState(() {});
    final left = _code.left;
    // Screen readers hear the countdown at one minute and at its end only,
    // not every second.
    if (left > Duration.zero &&
        left <= const Duration(minutes: 1) &&
        !identical(_minuteAnnouncedFor, pairing)) {
      _minuteAnnouncedFor = pairing;
      _announce('1 minute left to use this code.');
    }
    if (_code.isExpired) {
      if (!identical(_endAnnouncedFor, pairing)) {
        _endAnnouncedFor = pairing;
        _announce('This code ran out.');
      }
      if (!identical(_askedAtEnd, pairing)) {
        // Once more: it may have been used in its last seconds.
        _askedAtEnd = pairing;
        unawaited(_check());
      }
    }
  }

  void _announce(String message) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        message,
        Directionality.of(context),
      ),
    );
  }

  Future<void> _check() async {
    // Not while the app is in the background: the screen is not seen then.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == AppLifecycleState.hidden ||
        lifecycle == AppLifecycleState.paused) {
      return;
    }
    await _code.check();
  }

  Future<void> _share(String link) async {
    try {
      await shareText(link);
    } on Exception {
      if (mounted) {
        showAppSnackBar(
          context,
          "Couldn't open the share sheet. Copy the link.",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _code,
    builder: (context, _) {
      final children = <Widget>[
        if (_code.failure case final failure? when !failure.isQuiet)
          Callout.text(
            failure.message,
            kind: CalloutKind.error,
            icon: Icons.person_off,
            live: true,
          ),
        if (_code.pairing != null) ..._body(context),
      ];
      return ListView.separated(
        // Explicit padding drops the system insets a list pads by default.
        padding: screenPadding(context, top: 8),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, i) => children[i],
      );
    },
  );

  List<Widget> _body(BuildContext context) {
    if (_code.isUsed) return _used(context);
    if (_code.isExpired) return _expired(context);
    return _shown(context);
  }

  Widget _qr({required bool live}) => Center(
    child: live
        ? PairingQr(_code.link!, key: const Key('pairingQr'))
        : Opacity(
            opacity: 0.28,
            // A code that cannot be used is not worth reading out.
            child: ExcludeSemantics(
              child: PairingQr(_code.link!, key: const Key('pairingQr')),
            ),
          ),
  );

  List<Widget> _shown(BuildContext context) {
    final theme = Theme.of(context);
    final link = _code.link!;
    return [
      Text.rich(widget.intro, style: theme.textTheme.bodyLarge),
      _qr(live: true),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${widget.countdownLead} '),
            TextSpan(
              text: _minutesAndSeconds(_code.left),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const TextSpan(text: ' left.'),
          ],
        ),
        key: const Key('countdown'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium,
      ),
      Semantics(
        label: 'Pairing link',
        excludeSemantics: true,
        child: Container(
          key: const Key('pairingLink'),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            link,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          CopyButton(text: link, label: 'Copy link', filled: true),
          OutlinedButton.icon(
            key: const Key('shareLink'),
            onPressed: () => _share(link),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Share'),
          ),
        ],
      ),
      Callout.text(
        widget.warning,
        kind: CalloutKind.neutral,
        icon: Icons.warning_amber,
      ),
    ];
  }

  List<Widget> _used(BuildContext context) => [
    Callout(
      kind: CalloutKind.ok,
      icon: Icons.check_circle_outline,
      live: true,
      child: Text.rich(widget.joined(_code.usedBy!)),
    ),
    _qr(live: false),
    Align(
      alignment: Alignment.centerRight,
      child: FilledButton(
        key: const Key('done'),
        onPressed: widget.onDone,
        child: const Text('Done'),
      ),
    ),
  ];

  List<Widget> _expired(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _code.creating;
    return [
      Callout.text(
        widget.ranOut,
        kind: CalloutKind.error,
        icon: Icons.timer_off_outlined,
        live: true,
      ),
      _qr(live: false),
      Align(
        alignment: widget.centerNewCode
            ? Alignment.center
            : Alignment.centerLeft,
        child: FilledButton.icon(
          key: const Key('newCode'),
          onPressed: busy ? null : widget.onNewCode,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Make a new code'),
        ),
      ),
      if (widget.ranOutNote case final note?)
        Text(
          note,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
    ];
  }

  static String _minutesAndSeconds(Duration left) {
    // Rounded up, so the countdown reaches 0:00 only when the code expires.
    final seconds = (left.inMilliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}
