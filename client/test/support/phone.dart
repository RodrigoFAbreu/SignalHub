import 'package:flutter/widgets.dart';
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
