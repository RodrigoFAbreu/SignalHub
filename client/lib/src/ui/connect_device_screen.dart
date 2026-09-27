import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';

import '../app_controller.dart';

/// _Connect a device_, for an admin device: creates a one-time pairing code
/// for a new device and shows it as a QR code with its countdown, and as a
/// link to copy, as the admin page does.
class ConnectDeviceScreen extends StatefulWidget {
  const ConnectDeviceScreen({
    super.key,
    required this.controller,
    this.now = DateTime.now,
  });

  final AppController controller;

  /// The clock the countdown reads; replaced in tests.
  final DateTime Function() now;

  @override
  State<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends State<ConnectDeviceScreen> {
  AppController get _controller => widget.controller;

  final _name = TextEditingController();
  String? _error;
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    // Redraws the countdown; nothing to do while no code is shown.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_controller.pairing != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 100) {
      setState(() => _error = 'Enter a name of up to 100 characters');
      return;
    }
    setState(() => _error = null);
    final error = await _controller.createPairing(name);
    if (mounted) setState(() => _error = error);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Connect a device')),
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_controller.pairing != null)
            ..._pairing(context)
          else
            ..._form(context),
        ],
      ),
    ),
  );

  List<Widget> _form(BuildContext context) => [
    const Text(
      'Create a one-time pairing code, then open SignalHub on the new device '
      'and scan it, or paste its link. The new device is not an admin '
      'device; you can make it one afterwards.',
    ),
    const SizedBox(height: 16),
    TextField(
      key: const Key('pairingName'),
      controller: _name,
      maxLength: 100,
      decoration: const InputDecoration(
        labelText: 'Name of the new device',
        hintText: 'Pixel 8',
      ),
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _create(),
    ),
    if (_error case final error?)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          error,
          key: const Key('pairingError'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    FilledButton(
      key: const Key('createPairing'),
      onPressed: _controller.canCreatePairings && !_controller.creatingPairing
          ? _create
          : null,
      child: const Text('Create pairing code'),
    ),
  ];

  List<Widget> _pairing(BuildContext context) {
    final pairing = _controller.pairing!;
    final link = _controller.pairingLink!;
    final left = pairing.expiresAt.difference(widget.now());
    final expired = left <= Duration.zero;
    return [
      Text(
        'Pairing code for "${pairing.name}"',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 16),
      Center(
        child: expired
            ? const SizedBox.square(
                dimension: PairingQr.size,
                child: Icon(Icons.timer_off_outlined, size: 64),
              )
            : PairingQr(link, key: const Key('pairingQr')),
      ),
      const SizedBox(height: 8),
      Text(
        expired
            ? 'This code has expired.'
            : 'Expires in ${_minutesAndSeconds(left)}. It works once.',
        key: const Key('countdown'),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 16),
      if (!expired) ...[
        SelectableText(link, key: const Key('pairingLink')),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('copyLink'),
          onPressed: () => _copy(context, link),
          icon: const Icon(Icons.copy),
          label: const Text('Copy link'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Anyone with this code or link can pair a device until it is used '
          'or expires. Your devices are told when a device pairs.',
        ),
      ],
      TextButton(
        key: const Key('newPairing'),
        onPressed: _controller.clearPairing,
        child: const Text('Create another code'),
      ),
    ];
  }

  static Future<void> _copy(BuildContext context, String link) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: link));
    messenger.showSnackBar(
      const SnackBar(content: Text('Pairing link copied.')),
    );
  }

  static String _minutesAndSeconds(Duration left) {
    // Rounded up, so the countdown reaches 0:00 only when the code expires.
    final seconds = (left.inMilliseconds / 1000).ceil();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

/// [data] as a QR code, black on white with a quiet zone, whatever the
/// theme, so any camera reads it.
class PairingQr extends StatefulWidget {
  const PairingQr(this.data, {super.key});

  static const size = 240.0;

  final String data;

  @override
  State<PairingQr> createState() => _PairingQrState();
}

class _PairingQrState extends State<PairingQr> {
  // Encoded once per link, not on every tick of the countdown.
  late QrImage _image = _encode(widget.data);

  @override
  void didUpdateWidget(PairingQr old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) _image = _encode(widget.data);
  }

  // Level M survives a slightly blurry photo, as on the admin page.
  static QrImage _encode(String data) => QrImage(
    QrCode(
      payload: QrPayload.fromString(data),
      errorCorrectLevel: QrErrorCorrectLevel.medium,
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Pairing QR code',
    child: CustomPaint(
      size: const Size.square(PairingQr.size),
      painter: _QrPainter(_image),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);

  final QrImage image;

  // The quiet zone the QR standard asks for, in modules.
  static const _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final modules = image.moduleCount;
    // Whole pixels per module, so no seams show between modules.
    final scale = (size.shortestSide / (modules + 2 * _quiet)).floorToDouble();
    final offset = (size.shortestSide - scale * modules) / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final dark = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var row = 0; row < modules; row++) {
      for (var col = 0; col < modules; col++) {
        if (image.isDark(row, col)) {
          canvas.drawRect(
            Rect.fromLTWH(
              offset + col * scale,
              offset + row * scale,
              scale,
              scale,
            ),
            dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.image != image;
}
