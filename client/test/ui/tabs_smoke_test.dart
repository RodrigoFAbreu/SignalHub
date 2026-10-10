import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/app_controller.dart';

import '../support/harness.dart';
import '../support/phone.dart';

/// Every tab and the screens Settings opens, for each role, against a server
/// that knows none of the new endpoints: the screens say so and nothing
/// throws (one navigator is shared by the tabs, so floating buttons need their
/// own hero tags).
void main() {
  for (final role in ['BASIC', 'MOD', 'ADMIN']) {
    testWidgets('a $role walks through every tab without errors', (
      tester,
    ) async {
      final app = AppHarness(role: role);
      useDesignPhone(tester);
      await app.start(tester);

      for (final tab in app.controller.tabs) {
        await app.openTab(tester, tab);
        expect(find.byKey(Key('tab-${tab.name}')), findsOneWidget);
      }
      await app.openTab(tester, HomeTab.settings);
      await tester.tap(find.byKey(const Key('devices')));
      // The shimmer of the screen's skeleton never settles.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pageBack();
      await app.settle(tester);
      await tester.tap(find.byKey(const Key('aboutServer')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pageBack();
      await app.settle(tester);

      expect(tester.takeException(), isNull);
    });
  }
}
