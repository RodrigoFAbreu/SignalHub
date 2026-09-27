import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scans a QR code with the camera and returns what it holds, or `null` if
/// the owner went back. Opening it is what asks for the camera permission.
typedef PairingScanner = Future<String?> Function(BuildContext context);

Future<String?> scanPairingCode(BuildContext context) => Navigator.of(
  context,
).push<String>(MaterialPageRoute(builder: (_) => const PairingScannerScreen()));

class PairingScannerScreen extends StatefulWidget {
  const PairingScannerScreen({super.key});

  @override
  State<PairingScannerScreen> createState() => _PairingScannerScreenState();
}

class _PairingScannerScreenState extends State<PairingScannerScreen> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _scanned = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.firstOrNull?.rawValue;
    // The camera keeps detecting until the screen is gone: return once.
    if (value == null || _scanned) return;
    _scanned = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan pairing code')),
    body: MobileScanner(
      controller: _scanner,
      onDetect: _onDetect,
      errorBuilder: (context, error) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            error.errorCode == MobileScannerErrorCode.permissionDenied
                ? 'SignalHub needs the camera to scan a pairing code. Allow it '
                      'in the system settings, or paste the pairing link.'
                : 'The camera is not available. Paste the pairing link '
                      'instead.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
