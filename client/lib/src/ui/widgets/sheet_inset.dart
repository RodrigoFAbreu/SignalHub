import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The room a bottom sheet leaves under its content: the keyboard when it is
/// up, otherwise Android's navigation bar (or the home indicator), so the
/// last button is never behind a system bar. The keyboard's inset already
/// includes the bar, so the larger of the two is taken, never the sum.
double sheetBottomInset(BuildContext context) {
  final media = MediaQuery.of(context);
  return math.max(media.viewInsets.bottom, media.viewPadding.bottom);
}
