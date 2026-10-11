import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../connection/setup_failure.dart';
import 'app_settings.dart';
import 'pairing_scanner_screen.dart';
import 'widgets/banners.dart';
import 'widgets/sheet_inset.dart';

/// Connects the app to a SignalHub server, for someone who was invited: the
/// camera scans the invitation code, or its link is pasted. Setting up by
/// hand with a client key (`POST /api/v1/admin/clients`) is one tap away.
/// What can go wrong says what happened and what to do in one sentence, and
/// leaves the scanner usable.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.controller,
    this.scanner = scanPairingCode,
    this.openSettings = openAppSettings,
  });

  final AppController controller;

  /// The camera region; tests replace the camera.
  final PairingScannerBuilder scanner;

  /// Opens the phone's settings of this app, where the camera is allowed.
  final AppSettingsOpener openSettings;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pairingUri = TextEditingController();
  final _serverUrl = TextEditingController();
  final _clientKey = TextEditingController();

  bool _connecting = false;
  bool _byHand = false;
  bool _cameraOff = false;

  /// What went wrong with the last attempt; `null` before one, and when the
  /// owner changed what is being tried.
  SetupFailure? _failure;

  /// The code the last attempt used: tried again as it was, and not tried
  /// again while the camera keeps seeing it.
  String? _lastCode;

  /// Whether the device is here because the server stopped accepting it.
  late bool _signedOut = widget.controller.signedOut;

  @override
  void dispose() {
    _pairingUri.dispose();
    _serverUrl.dispose();
    _clientKey.dispose();
    super.dispose();
  }

  void _onCode(String code) {
    // The camera reads the same code many times a second.
    if (_connecting || code == _lastCode) return;
    _pairWith(code);
  }

  Future<void> _pairWith(String code) async {
    _lastCode = code;
    await _attempt(() => widget.controller.pair(code));
  }

  Future<void> _connect() => _attempt(
    () => widget.controller.connect(_serverUrl.text, _clientKey.text),
  );

  Future<void> _attempt(Future<SetupFailure?> Function() run) async {
    setState(() {
      _connecting = true;
      _failure = null;
      _signedOut = false;
    });
    final failure = await run();
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _failure = failure;
    });
  }

  Future<void> _pasteLink() async {
    // What was copied is offered, if it looks like a link to pair with.
    final clipboard = await _clipboardText();
    if (!mounted) return;
    if (clipboard != null && clipboard.trim().startsWith('signalhub://')) {
      _pairingUri.text = clipboard.trim();
    }
    final link = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PasteLinkSheet(controller: _pairingUri),
    );
    if (link != null && mounted) await _pairWith(link);
  }

  /// What was copied, or `null` when the clipboard cannot be read: the link
  /// is typed or pasted into the field instead.
  Future<String?> _clipboardText() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Back to a scanner that tries a code again, also one it just tried.
  void _scanAnother() => setState(() {
    _failure = null;
    _lastCode = null;
  });

  void _tryAgain() {
    final code = _lastCode;
    if (code != null) _pairWith(code);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        // A column matches its children by key, so the camera keeps running
        // when a banner appears above it.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _byHand ? _byHandChildren(context) : _scanChildren(context),
        ),
      ),
    ),
  );

  // ---- Scanning ----

  List<Widget> _scanChildren(BuildContext context) {
    final theme = Theme.of(context);
    final failure = _failure;
    // The server could not be reached or answered with an error: nothing was
    // used up, so the same code is tried again from here.
    final retryable = failure != null && failure.canRetry && _lastCode != null;
    final pristine = failure == null && !_signedOut && !_cameraOff;
    return [
      Text('Connect to SignalHub', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 16),
      if (pristine) ...[
        Text(
          'Scan the code someone shared with you, or paste its link.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
      ],
      if (_signedOut && failure == null) ...[
        const AppBanner(
          icon: Icons.link_off,
          message: noLongerConnectedMessage,
          margin: EdgeInsets.zero,
          iconAtTop: true,
        ),
        const SizedBox(height: 16),
      ],
      if (failure != null) ...[
        AppBanner(
          icon: _icon(failure.kind),
          message: failure.message,
          error: true,
          margin: EdgeInsets.zero,
          iconAtTop: true,
        ),
        const SizedBox(height: 16),
      ] else if (_cameraOff) ...[
        const AppBanner(
          icon: Icons.no_photography_outlined,
          message:
              "SignalHub can't use the camera, so it can't scan. Paste the "
              "link instead, or allow the camera in your phone's settings.",
          margin: EdgeInsets.zero,
          iconAtTop: true,
        ),
        const SizedBox(height: 16),
      ],
      if (retryable)
        _retryButtons()
      else ...[
        _cameraRegion(context),
        const SizedBox(height: 16),
        _pasteButtons(),
        if (pristine) ...[
          const SizedBox(height: 16),
          Text(
            'A code works once and for a few minutes. If it has run out, ask '
            'for a new one.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _clientKeyLink(theme),
      ],
    ];
  }

  static IconData _icon(SetupFailureKind kind) => switch (kind) {
    SetupFailureKind.notInvitation ||
    SetupFailureKind.webSignIn => Icons.qr_code_2,
    SetupFailureKind.codeRejected => Icons.timer_off_outlined,
    SetupFailureKind.unreachable => Icons.cloud_off,
    _ => Icons.error_outline,
  };

  Widget _cameraRegion(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (_cameraOff) {
      return Opacity(
        opacity: 0.5,
        child: Container(
          key: const Key('cameraOff'),
          height: scannerOffHeight,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(
            'camera off',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return Stack(
      key: const Key('camera'),
      children: [
        widget.scanner(
          context,
          PairingScanHandlers(
            onCode: _onCode,
            onCameraUnavailable: () => setState(() => _cameraOff = true),
          ),
        ),
        // The code is being redeemed: nothing more is read meanwhile.
        if (_connecting)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.scrim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }

  Widget _pasteButtons() {
    final paste = _cameraOff
        ? FilledButton.icon(
            key: const Key('pasteLink'),
            onPressed: _connecting ? null : _pasteLink,
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste link'),
          )
        : FilledButton.tonalIcon(
            key: const Key('pasteLink'),
            onPressed: _connecting ? null : _pasteLink,
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste link'),
          );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        paste,
        if (_cameraOff)
          TextButton(
            key: const Key('openSettings'),
            onPressed: widget.openSettings,
            child: const Text('Open settings'),
          ),
      ],
    );
  }

  Widget _retryButtons() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      FilledButton.icon(
        key: const Key('tryAgain'),
        onPressed: _connecting ? null : _tryAgain,
        icon: _connecting ? const _Spinner() : const Icon(Icons.refresh),
        label: const Text('Try again'),
      ),
      TextButton(
        key: const Key('scanAnother'),
        onPressed: _connecting ? null : _scanAnother,
        child: const Text('Scan another'),
      ),
    ],
  );

  Widget _clientKeyLink(ThemeData theme) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton(
        key: const Key('byHand'),
        style: TextButton.styleFrom(
          foregroundColor: theme.colorScheme.onSurfaceVariant,
          padding: EdgeInsets.zero,
          minimumSize: const Size(48, 48),
        ),
        onPressed: _connecting
            ? null
            : () => setState(() {
                _byHand = true;
                _failure = null;
              }),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: 'With a client key',
                style: style?.copyWith(decoration: TextDecoration.underline),
              ),
              TextSpan(text: ' instead', style: style),
            ],
          ),
        ),
      ),
    );
  }

  // ---- By hand, with a client key ----

  List<Widget> _byHandChildren(BuildContext context) {
    final failure = _failure;
    // An address that cannot be reached gets the sentence of an unreachable
    // server under the address field.
    final addressError = switch (failure?.kind) {
      SetupFailureKind.badAddress ||
      SetupFailureKind.unreachable ||
      SetupFailureKind.serverProblem ||
      SetupFailureKind.unexpectedAnswer => failure!.message,
      _ => null,
    };
    final keyError = switch (failure?.kind) {
      SetupFailureKind.badKey ||
      SetupFailureKind.keyRejected => failure!.message,
      _ => null,
    };
    return [
      Text(
        'With a client key',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('serverUrl'),
        controller: _serverUrl,
        enabled: !_connecting,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: 'Server address',
          hintText: 'https://signalhub.example.org',
          border: const OutlineInputBorder(),
          errorText: addressError,
          errorMaxLines: 3,
          suffixIcon: addressError == null ? null : const Icon(Icons.error),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const Key('clientKey'),
        controller: _clientKey,
        enabled: !_connecting,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: 'Client key',
          hintText: 'shck1_…',
          border: const OutlineInputBorder(),
          errorText: keyError,
          errorMaxLines: 3,
          suffixIcon: keyError == null ? null : const Icon(Icons.error),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          TextButton(
            key: const Key('backToScanning'),
            onPressed: _connecting
                ? null
                : () => setState(() {
                    _byHand = false;
                    _failure = null;
                  }),
            child: const Text('Back to scanning'),
          ),
          FilledButton.icon(
            key: const Key('connect'),
            onPressed: _connecting ? null : _connect,
            icon: _connecting ? const _Spinner() : null,
            label: const Text('Connect'),
          ),
        ],
      ),
    ];
  }
}

/// The spinner a working button shows in its icon slot.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

/// The keyboard and screen reader way to give the invitation: its link.
class _PasteLinkSheet extends StatelessWidget {
  const _PasteLinkSheet({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + sheetBottomInset(context)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Paste link', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          key: const Key('pairingUri'),
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Invitation link',
            hintText: 'signalhub://pair?…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton(
            key: const Key('pair'),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Connect'),
          ),
        ),
      ],
    ),
  );
}
