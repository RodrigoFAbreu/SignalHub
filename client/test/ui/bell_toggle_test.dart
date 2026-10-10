import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/ui/widgets/bell_toggle.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    BellToggle bell, {
    Brightness brightness = Brightness.dark,
    bool reduceMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: brightness),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: Center(child: bell)),
      ),
    ),
  );

  Finder circle() => find.descendant(
    of: find.byType(BellToggle),
    matching: find.byType(Container),
  );

  BoxDecoration decoration(WidgetTester tester) =>
      tester.widget<Container>(circle()).decoration! as BoxDecoration;

  ColorScheme colors(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(BellToggle))).colorScheme;

  for (final brightness in Brightness.values) {
    testWidgets('subscribed: a filled secondary circle, $brightness', (
      tester,
    ) async {
      await show(
        tester,
        BellToggle(name: 'ci', subscribed: true, onPressed: () {}),
        brightness: brightness,
      );

      expect(decoration(tester).color, colors(tester).secondaryContainer);
      expect(decoration(tester).border, isNull);
      final icon = tester.widget<Icon>(find.byKey(const Key('bellIcon')));
      expect(icon.icon, Icons.notifications_active);
      expect(icon.color, colors(tester).onSecondaryContainer);
    });

    testWidgets('not subscribed: a 1 dp outline, $brightness', (tester) async {
      await show(
        tester,
        BellToggle(name: 'ci', subscribed: false, onPressed: () {}),
        brightness: brightness,
      );

      expect(decoration(tester).color, isNull);
      final border = decoration(tester).border! as Border;
      expect(border.top.width, 1);
      expect(border.top.color, colors(tester).outline);
      final icon = tester.widget<Icon>(find.byKey(const Key('bellIcon')));
      expect(icon.icon, Icons.notifications_outlined);
      expect(icon.color, colors(tester).onSurfaceVariant);
    });
  }

  testWidgets('is a 40 dp circle in a 48 dp target', (tester) async {
    await show(
      tester,
      BellToggle(name: 'ci', subscribed: true, onPressed: () {}),
    );

    expect(tester.getSize(find.byType(BellToggle)), const Size(48, 48));
    expect(tester.getSize(circle()), const Size(40, 40));
  });

  testWidgets('in flight: a 24 dp ring of 2.5 dp, and taps are ignored', (
    tester,
  ) async {
    var taps = 0;
    await show(
      tester,
      BellToggle(
        name: 'ci',
        subscribed: false,
        changingTo: true,
        onPressed: () => taps++,
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final ring = find.byKey(const Key('bellRing'));
    expect(tester.getSize(ring), const Size(24, 24));
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.descendant(
              of: ring,
              matching: find.byType(CircularProgressIndicator),
            ),
          )
          .strokeWidth,
      2.5,
    );
    expect(find.byKey(const Key('bellIcon')), findsNothing);
    // Subscribing: the circle is the one it moves to, filled.
    expect(decoration(tester).color, colors(tester).secondaryContainer);
    await tester.tap(find.byType(BellToggle));
    expect(taps, 0);
  });

  testWidgets('unsubscribing in flight keeps the outline', (tester) async {
    await show(
      tester,
      BellToggle(
        name: 'ci',
        subscribed: true,
        changingTo: false,
        onPressed: () {},
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(decoration(tester).color, isNull);
    expect((decoration(tester).border! as Border).top.width, 1);
    expect(find.byKey(const Key('bellRing')), findsOneWidget);
  });

  testWidgets('under reduced motion the ring stays and does not turn', (
    tester,
  ) async {
    await show(
      tester,
      BellToggle(
        name: 'ci',
        subscribed: false,
        changingTo: true,
        onPressed: () {},
      ),
      reduceMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 200));

    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, isNotNull);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('without a handler it is greyed to 38 % and ignores taps', (
    tester,
  ) async {
    await show(tester, const BellToggle(name: 'ci', subscribed: true));

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byType(BellToggle),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.38);
    await tester.tap(find.byType(BellToggle));
  });

  testWidgets('a tap calls the handler once', (tester) async {
    var taps = 0;
    await show(
      tester,
      BellToggle(name: 'ci', subscribed: true, onPressed: () => taps++),
    );

    await tester.tap(find.byType(BellToggle));

    expect(taps, 1);
  });

  group('the name a screen reader speaks', () {
    Future<String> label(WidgetTester tester, BellToggle bell) async {
      final handle = tester.ensureSemantics();
      await show(tester, bell);
      final semantics = tester.getSemantics(find.byType(BellToggle));
      final label = semantics.label;
      handle.dispose();
      return label;
    }

    testWidgets('subscribed', (tester) async {
      expect(
        await label(
          tester,
          BellToggle(name: 'ci-pipeline', subscribed: true, onPressed: () {}),
        ),
        'Subscribed to ci-pipeline. Double tap to unsubscribe.',
      );
    });

    testWidgets('not subscribed', (tester) async {
      expect(
        await label(
          tester,
          BellToggle(name: 'price-watch', subscribed: false, onPressed: () {}),
        ),
        'Not subscribed to price-watch. Double tap to subscribe.',
      );
    });

    testWidgets('subscribing and unsubscribing', (tester) async {
      expect(
        await label(
          tester,
          const BellToggle(name: 'ana', subscribed: false, changingTo: true),
        ),
        'Subscribing to ana',
      );
      expect(
        await label(
          tester,
          const BellToggle(name: 'ana', subscribed: true, changingTo: false),
        ),
        'Unsubscribing from ana',
      );
    });
  });
}
