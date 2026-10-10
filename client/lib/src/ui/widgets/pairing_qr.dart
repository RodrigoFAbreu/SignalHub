import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

/// [data] as a QR code, black on white with a quiet zone, whatever the
/// theme, so any camera reads it.
class PairingQr extends StatefulWidget {
  const PairingQr(this.data, {super.key, this.size = defaultSize});

  static const defaultSize = 200.0;

  final String data;

  /// Side of the square, quiet zone included.
  final double size;

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
      size: Size.square(widget.size),
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
