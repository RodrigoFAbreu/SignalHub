import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../connection/web_sign_in_link.dart';
import '../features/web_sign_in_controller.dart';
import 'pairing_scanner_screen.dart';
import 'widgets/banners.dart';
import 'widgets/busy_button.dart';

/// _Settings › Sign in a browser_, for every role: the camera reads the code a
/// web page shows, or _Type a code_ takes the short one under it, and a sheet
/// then asks _Sign in this browser?_ naming the browser and system. Only the
/// person's _Sign in_ signs it in; _Cancel_ tells the page it was cancelled.
///
/// [link] is a sign-in link the phone opened (the page's _Open the app_
/// button): it is read at once, with no camera, and goes to the same sheet.
class SignInBrowserScreen extends StatefulWidget {
  const SignInBrowserScreen({
    super.key,
    required this.controller,
    this.scanner = scanWebSignInCode,
    this.link,
  });

  final AppController controller;

  /// The camera region; tests replace the camera.
  final PairingScannerBuilder scanner;
  final String? link;

  @override
  State<SignInBrowserScreen> createState() => _SignInBrowserScreenState();
}

class _SignInBrowserScreenState extends State<SignInBrowserScreen> {
  late final WebSignInController _sign = WebSignInController(
    widget.controller,
    serverUrl: widget.controller.credentials?.baseUrl ?? '',
  );
  final _code = TextEditingController();

  bool _typing = false;
  bool _cameraOff = false;
  bool _sheetOpen = false;
  bool _closed = false;
  bool _devicesReread = false;

  /// A link is being read: the camera does not start behind it, which would
  /// ask for the camera for a code that is already in hand.
  late bool _fromLink = widget.link != null;
  bool _linkRead = false;

  @override
  void initState() {
    super.initState();
    _sign.addListener(_onChange);
    final link = widget.link;
    if (link != null) {
      // Not while building: reading notifies the controller's listeners.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _linkRead = true;
        _sign.readScanned(link);
      });
    }
  }

  @override
  void dispose() {
    _closed = true;
    _sign.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onChange() {
    if (_closed) return;
    if (_fromLink && _linkRead && _sign.step == SignInStep.scanning) {
      setState(() => _fromLink = false);
    }
    if (_sign.step == SignInStep.confirming && !_sheetOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSheet());
    }
    if (_sign.step == SignInStep.done && !_devicesReread) {
      // The browser is a device now.
      _devicesReread = true;
      widget.controller.deviceList.load();
    }
  }

  Future<void> _showSheet() async {
    if (!mounted || _sheetOpen || _sign.step != SignInStep.confirming) return;
    _sheetOpen = true;
    final signedIn = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConfirmSheet(controller: _sign),
    );
    _sheetOpen = false;
    if (signedIn != true && _sign.step == SignInStep.confirming) {
      await _sign.cancel();
    }
  }

  void _onCode(String code) => _sign.readScanned(code);

  void _continue() {
    if (_sign.step != SignInStep.scanning) return;
    _sign.readTyped(_code.text);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Back from the code entry goes back to the camera.
    canPop: !_typing,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) setState(() => _typing = false);
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Sign in a browser'),
        titleSpacing: 0,
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
          listenable: _sign,
          builder: (context, _) => _sign.step == SignInStep.done
              ? _Done(name: _sign.signedIn ?? 'The browser')
              : (_typing ? _typeBody(context) : _scanBody(context)),
        ),
      ),
    ),
  );

  // ---- The camera ----

  Widget _scanBody(BuildContext context) {
    final theme = Theme.of(context);
    final failure = _sign.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null)
          _failureBanner(failure)
        else if (_cameraOff)
          const AppBanner(
            icon: Icons.no_photography_outlined,
            message:
                "SignalHub can't use the camera, so it can't scan. Type the "
                "code instead, or allow the camera in your phone's settings.",
            iconAtTop: true,
          ),
        Expanded(child: _cameraRegion(context)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            _cameraOff
                ? 'Type the code the page shows.'
                : 'Point the camera at the code on the page.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Center(
            child: TextButton(
              key: const Key('typeCode'),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => setState(() {
                _typing = true;
                _sign.clearFailure();
              }),
              child: const Text('Type a code'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _cameraRegion(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final checking =
        _sign.step == SignInStep.checking ||
        (_fromLink && _sign.step == SignInStep.scanning);
    return Container(
      margin: const EdgeInsets.all(12),
      child: Stack(
        key: const Key('camera'),
        fit: StackFit.expand,
        children: [
          if (_cameraOff)
            Container(
              key: const Key('cameraOff'),
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
            )
          else if (!_fromLink)
            widget.scanner(
              context,
              PairingScanHandlers(
                onCode: _onCode,
                onCameraUnavailable: () => setState(() => _cameraOff = true),
              ),
            ),
          // Where the code goes, as a viewfinder.
          if (!_cameraOff)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.all(60),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.primary, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          // The code is being read: nothing more is read meanwhile.
          if (checking)
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.scrim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Widget _failureBanner(SignInFailure failure) => AppBanner(
    key: const Key('signInFailure'),
    icon: _icon(failure.kind),
    message: failure.message,
    error: true,
    iconAtTop: true,
    actionLabel: failure.canRetry ? 'Try again' : null,
    onAction: failure.canRetry ? _sign.retry : null,
  );

  static IconData _icon(SignInFailureKind kind) => switch (kind) {
    SignInFailureKind.notSignInCode => Icons.qr_code_2,
    SignInFailureKind.otherServer => Icons.dns_outlined,
    SignInFailureKind.wrongCode ||
    SignInFailureKind.gone => Icons.timer_off_outlined,
    SignInFailureKind.tooManyTries => Icons.hourglass_top,
    SignInFailureKind.offline => Icons.cloud_off,
    SignInFailureKind.other => Icons.error_outline,
  };

  // ---- The typed code ----

  Widget _typeBody(BuildContext context) {
    final theme = Theme.of(context);
    final failure = _sign.failure;
    // A code that is wrong, or tried too often, is said under the field; the
    // rest is about the server and not about the field.
    final fieldError =
        failure != null &&
            (failure.kind == SignInFailureKind.wrongCode ||
                failure.kind == SignInFailureKind.tooManyTries)
        ? failure.message
        : null;
    final checking = _sign.step != SignInStep.scanning;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null && fieldError == null) ...[
            _failureBanner(failure),
            const SizedBox(height: 8),
          ],
          Text(
            'Enter the code the page shows.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            key: const Key('signInCode'),
            controller: _code,
            autofocus: true,
            enabled: !checking,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 3),
            decoration: InputDecoration(
              labelText: 'Code',
              border: const OutlineInputBorder(),
              errorText: fieldError,
              errorMaxLines: 3,
              suffixIcon: fieldError == null ? null : const Icon(Icons.error),
            ),
            onChanged: (_) {
              _sign.clearFailure();
              setState(() {});
            },
            onSubmitted: (_) => _canContinue ? _continue() : null,
          ),
          const SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: BusyFilledButton(
              key: const Key('continueCode'),
              label: 'Continue',
              busy: _sign.step == SignInStep.checking,
              onPressed: _canContinue ? _continue : null,
            ),
          ),
        ],
      ),
    );
  }

  /// The button stays off until the field holds as many characters as a code.
  bool get _canContinue => WebSignInCode.isComplete(_code.text);
}

/// The question: which browser, and what signing it in means. Answers by
/// popping `true` once the browser is signed in or the sign-in is over.
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.controller});

  final WebSignInController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final asked = controller.request;
      final approving = controller.step == SignInStep.approving;
      final failure = controller.failure;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sign in this browser?',
                // The drawing's sheet title: 20 on 26.
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  height: 26 / 20,
                ),
              ),
              const SizedBox(height: 14),
              _Fact(
                icon: Icons.language,
                text: asked?.browserName ?? 'A browser',
                bold: true,
              ),
              const SizedBox(height: 14),
              const _Fact(icon: Icons.schedule, text: 'Asked just now'),
              const SizedBox(height: 14),
              Text(
                'Only sign in a browser you are looking at right now. It can '
                'read and send what you can for 30 days, or until you sign it '
                'out.',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                  height: 18 / 13,
                  color: colors.onSurfaceVariant,
                ),
              ),
              if (failure != null) ...[
                const SizedBox(height: 14),
                Text(
                  key: const Key('signInSheetFailure'),
                  failure.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: const Key('cancelSignIn'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: approving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  BusyFilledButton(
                    key: const Key('approveSignIn'),
                    label: 'Sign in',
                    busy: approving,
                    onPressed: () async {
                      await controller.approve();
                      if (context.mounted &&
                          controller.step != SignInStep.confirming) {
                        Navigator.of(context).pop(true);
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.bold = false});

  final IconData icon;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              height: 18 / 13,
              fontWeight: bold ? FontWeight.w500 : null,
              color: bold ? colors.onSurface : colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The browser is signed in.
class _Done extends StatelessWidget {
  const _Done({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                size: 32,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                'Browser signed in',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20,
                  height: 26 / 20,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '$name can now use your SignalHub for 30 days. You can sign it '
              'out any time in Devices.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('signInDone'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
