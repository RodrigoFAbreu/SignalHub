import 'package:share_plus/share_plus.dart';

/// Hands [text] to the platform's share sheet, as text: a pairing link is
/// not tappable in many chat apps, so the other device pastes it.
Future<void> shareText(String text) =>
    SharePlus.instance.share(ShareParams(text: text));
