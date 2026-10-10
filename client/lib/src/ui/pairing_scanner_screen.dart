import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// What the camera region of the setup screen tells the screen.
class PairingScanHandlers {
  const PairingScanHandlers({
    required this.onCode,
    required this.onCameraUnavailable,
  });

  /// A QR code was read: what it holds. The camera keeps reading until the
  /// screen is gone, so the same code arrives again and again.
  final ValueChanged<String> onCode;

  /// The camera cannot be used: not allowed, or not there.
  final VoidCallback onCameraUnavailable;
}

/// Builds the camera region of the setup screen. Tests replace the camera.
typedef PairingScannerBuilder = Widget Function(
  BuildContext context,
  PairingScanHandlers handlers,
);

/// The camera region's height on the setup screen, and its height when the
/// camera is off.
const scannerHeight = 220.0;
const scannerOffHeight = 120.0;

/// The camera of the setup screen: a rounded region that reads QR codes. Its
/// accessible name says what to point at. Showing it is what asks for the
/// camera permission.
Widget scanPairingCode(BuildContext context, PairingScanHandlers handlers) =>
    PairingScannerView(handlers: handlers);

class PairingScannerView extends StatefulWidget {
  const PairingScannerView({super.key, required this.handlers});

  final PairingScanHandlers handlers;

  @override
  State<PairingScannerView> createState() => _PairingScannerViewState();
}

class _PairingScannerViewState extends State<PairingScannerView> {
  final _scanner = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _reportedUnavailable = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value != null) widget.handlers.onCode(value);
  }

  /// The error is known while building, which may not change the screen
  /// above: it is told once, after the frame.
  Widget _unavailable(BuildContext context, MobileScannerException error) {
    if (!_reportedUnavailable) {
      _reportedUnavailable = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.handlers.onCameraUnavailable(),
      );
    }
    return const SizedBox.expand();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Camera, point at the invitation code',
    child: ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: scannerHeight,
        child: MobileScanner(
          controller: _scanner,
          onDetect: _onDetect,
          errorBuilder: _unavailable,
        ),
      ),
    ),
  );
}
