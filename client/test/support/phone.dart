import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The logical height of the navigation bar drawn over the app.
const navigationBarHeight = 48.0;

/// Sizes the test view as a large phone, 1080 x 2340 pixels at 2.625x
/// (about 411 x 891), that draws edge to edge: its status bar and a button
/// navigation bar sit over the app, as system insets.
void useEdgeToEdgePhone(WidgetTester tester) {
  const ratio = 2.625;
  const insets = FakeViewPadding(
    top: 40 * ratio,
    bottom: navigationBarHeight * ratio,
  );
  tester.view
    ..physicalSize = const Size(1080, 2340)
    ..devicePixelRatio = ratio
    ..padding = insets
    ..viewPadding = insets;
  addTearDown(tester.view.reset);
}

/// Drags the scrollable of [screen] until it is at its end. A lazy list
/// knows its full length only once built, so one long drag stops short.
/// Pumps without settling: a screen may tick every second.
Future<void> scrollToEnd(WidgetTester tester, Finder screen) async {
  final scrollable = find
      .descendant(of: screen, matching: find.byType(Scrollable))
      .first;
  final position = tester.state<ScrollableState>(scrollable).position;
  while (position.pixels < position.maxScrollExtent) {
    await tester.drag(scrollable, const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }
}

/// Expects [finder] wholly on screen, above the navigation bar.
void expectClearOfNavigationBar(WidgetTester tester, Finder finder) {
  final view = tester.view;
  final height = view.physicalSize.height / view.devicePixelRatio;
  final rect = tester.getRect(finder);
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(height - navigationBarHeight));
}

/// Sizes the test view as the design's phone: 412 x 892 dp at 2x, with the
/// drawing's 28 dp status bar as a top inset and no navigation bar. `size`
/// is in dp; 360 x 900 is the narrowest the screens are checked at.
void useDesignPhone(
  WidgetTester tester, {
  Size size = const Size(412, 892),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
}) {
  const ratio = 2.0;
  const insets = FakeViewPadding(top: 28 * ratio);
  tester.view
    ..physicalSize = size * ratio
    ..devicePixelRatio = ratio
    ..padding = insets
    ..viewPadding = insets;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}
