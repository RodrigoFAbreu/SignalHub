import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/models/users.dart';
import 'package:signalhub_client/src/ui/widgets/banners.dart';
import 'package:signalhub_client/src/ui/widgets/copy_button.dart';
import 'package:signalhub_client/src/ui/widgets/dialogs.dart';
import 'package:signalhub_client/src/ui/widgets/empty_state.dart';
import 'package:signalhub_client/src/ui/widgets/search_field.dart';
import 'package:signalhub_client/src/ui/widgets/skeleton.dart';
import 'package:signalhub_client/src/ui/widgets/snack.dart';
import 'package:signalhub_client/src/ui/widgets/tags.dart';

/// The pieces every new screen is built from (docs/design/users/DESIGN.md).
void main() {
  Widget app(Widget child, {Brightness brightness = Brightness.dark}) =>
      MaterialApp(
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          brightness: brightness,
        ),
        home: Scaffold(body: child),
      );

  group('RoleTag', () {
    testWidgets('says the role in a word, one form for each', (tester) async {
      await tester.pumpWidget(
        app(
          Column(children: [for (final role in UserRole.values) RoleTag(role)]),
        ),
      );

      for (final word in ['Admin', 'Mod', 'Basic']) {
        expect(find.text(word), findsOneWidget);
      }
      final colors = Theme.of(tester.element(find.text('Admin'))).colorScheme;
      Decoration decoration(String word) => tester
          .widget<Container>(
            find.ancestor(
              of: find.text(word),
              matching: find.byType(Container),
            ),
          )
          .decoration!;
      expect(
        (decoration('Admin') as BoxDecoration).color,
        colors.primaryContainer,
      );
      expect(
        (decoration('Mod') as BoxDecoration).color,
        colors.secondaryContainer,
      );
      // Basic is outlined, and no tag is ever red.
      final basic = decoration('Basic') as BoxDecoration;
      expect(basic.border, isNotNull);
      expect(basic.color, Colors.transparent);
      for (final word in ['Admin', 'Mod', 'Basic']) {
        final text = tester.widget<Text>(find.text(word));
        expect(text.style?.color, isNot(colors.error));
      }
      expect(tester.getSize(find.byType(RoleTag).first).height, 24);
    });
  });

  group('LabelTag', () {
    testWidgets('is 20 dp high and never wraps', (tester) async {
      await tester.pumpWidget(
        app(
          const Column(
            children: [
              LabelTag('Yours'),
              LabelTag('This device', style: LabelTagStyle.primary),
            ],
          ),
        ),
      );

      expect(tester.getSize(find.byType(LabelTag).first).height, 20);
      expect(find.text('Yours'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      final colors = Theme.of(tester.element(find.text('Yours'))).colorScheme;
      final yours = tester.widget<Container>(
        find.ancestor(of: find.text('Yours'), matching: find.byType(Container)),
      );
      expect(
        (yours.decoration! as BoxDecoration).color,
        colors.surfaceContainerHighest,
      );
    });
  });

  group('AppBanner', () {
    testWidgets('a neutral banner has an action and is 12 dp round', (
      tester,
    ) async {
      var tried = 0;
      await tester.pumpWidget(
        app(
          AppBanner(
            icon: Icons.cloud_off,
            message: 'You are offline.',
            actionLabel: 'Try again',
            onAction: () => tried++,
          ),
        ),
      );

      expect(find.text('You are offline.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(tried, 1);
      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppBanner),
          matching: find.byType(Container),
        ),
      );
      final decoration = box.decoration! as BoxDecoration;
      final colors = Theme.of(tester.element(find.byType(AppBanner)))
          .colorScheme;
      expect(decoration.color, colors.surfaceContainerHigh);
      expect(decoration.borderRadius, BorderRadius.circular(12));
      expect(
        tester.getSize(find.byType(AppBanner)).height,
        greaterThanOrEqualTo(56),
      );
    });

    testWidgets('an error banner uses the error container', (tester) async {
      await tester.pumpWidget(
        app(
          const AppBanner(
            icon: Icons.block,
            message: 'The host disabled this producer.',
            error: true,
          ),
        ),
      );

      final box = tester.widget<Container>(
        find.descendant(
          of: find.byType(AppBanner),
          matching: find.byType(Container),
        ),
      );
      final colors = Theme.of(tester.element(find.byType(AppBanner)))
          .colorScheme;
      expect((box.decoration! as BoxDecoration).color, colors.errorContainer);
    });
  });

  group('EmptyState', () {
    testWidgets('an icon, a title, a sentence and one action', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        app(
          EmptyState(
            icon: Icons.sensors,
            title: 'No producers yet',
            body: 'A producer is anything that sends events.',
            actionLabel: 'New producer',
            actionIcon: Icons.add,
            onAction: () => pressed = true,
          ),
        ),
      );

      expect(find.text('No producers yet'), findsOneWidget);
      expect(
        find.text('A producer is anything that sends events.'),
        findsOneWidget,
      );
      expect(tester.widget<Icon>(find.byIcon(Icons.sensors)).size, 48);
      final title = tester.widget<Text>(find.text('No producers yet'));
      final theme = Theme.of(tester.element(find.text('No producers yet')));
      expect(title.style, theme.textTheme.titleLarge);
      await tester.tap(find.text('New producer'));
      expect(pressed, isTrue);
    });

    testWidgets('without an action or a sentence it is just the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const EmptyState(icon: Icons.check, title: 'Nothing here')),
      );

      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Nothing here'), findsOneWidget);
    });
  });

  group('SkeletonRows', () {
    testWidgets('shows rows of the real shape and says it is loading', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(app(const SkeletonRows(count: 5)));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(Padding), findsWidgets);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('the shimmer is still under reduced motion', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: app(const SkeletonRows()),
        ),
      );

      // Nothing keeps asking for frames, so the tree can settle.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('showConfirmDialog', () {
    Future<bool?> open(
      WidgetTester tester, {
      bool destructive = false,
      String title = 'Revoke this key?',
    }) async {
      bool? answer;
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => answer = await showConfirmDialog(
                context,
                title: title,
                message: 'It never works again.',
                action: 'Revoke',
                destructive: destructive,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('names the thing and says what happens', (tester) async {
      await open(tester);

      expect(find.text('Revoke this key?'), findsOneWidget);
      expect(find.text('It never works again.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Revoke'), findsOneWidget);
    });

    testWidgets('an action that cannot be taken back is in the error colour', (
      tester,
    ) async {
      await open(tester, destructive: true);

      final button = tester.widget<TextButton>(
        find.byKey(const Key('confirm')),
      );
      final colors = Theme.of(tester.element(find.text('Revoke'))).colorScheme;
      expect(button.style?.foregroundColor?.resolve({}), colors.error);
    });

    testWidgets('a reversible action keeps the primary colour', (tester) async {
      await open(tester);

      final button = tester.widget<TextButton>(
        find.byKey(const Key('confirm')),
      );
      expect(button.style, isNull);
    });

    testWidgets('Cancel and a tap outside answer no, the action yes', (
      tester,
    ) async {
      bool? answer;
      Future<void> ask() async {
        await tester.pumpWidget(
          app(
            Builder(
              builder: (context) => TextButton(
                onPressed: () async => answer = await showConfirmDialog(
                  context,
                  title: 'Disable it?',
                  message: 'Its keys stop working.',
                  action: 'Disable',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await ask();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await ask();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(answer, isFalse);

      await ask();
      await tester.tap(find.byKey(const Key('confirm')));
      await tester.pumpAndSettle();
      expect(answer, isTrue);
    });

    testWidgets('a long title is never cut', (tester) async {
      await open(
        tester,
        title: 'Revoke "Ana - Pixel with a very long name indeed"?',
      );

      final title = tester.widget<Text>(
        find.text('Revoke "Ana - Pixel with a very long name indeed"?'),
      );
      expect(title.overflow, isNull);
      expect(title.maxLines, isNull);
    });
  });

  group('showAppSnackBar', () {
    Future<void> show(
      WidgetTester tester, {
      String? actionLabel,
      VoidCallback? onAction,
    }) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppSnackBar(
                context,
                "Couldn't subscribe to ci-pipeline. Try again.",
                actionLabel: actionLabel,
                onAction: onAction,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a message with Retry runs the action', (tester) async {
      var retried = 0;
      await show(tester, actionLabel: 'Retry', onAction: () => retried++);

      expect(
        find.text("Couldn't subscribe to ci-pipeline. Try again."),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry'));
      expect(retried, 1);
    });

    testWidgets('is gone after six seconds', (tester) async {
      await show(tester);
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a newer message replaces an older one', (tester) async {
      await show(tester);
      showAppSnackBar(tester.element(find.text('open')), 'Second');
      await tester.pumpAndSettle(const Duration(milliseconds: 100));

      expect(find.text('Second'), findsOneWidget);
      expect(
        find.text("Couldn't subscribe to ci-pipeline. Try again."),
        findsNothing,
      );
    });
  });

  group('CopyButton', () {
    late List<String> copied;
    late bool refuse;

    setUp(() {
      copied = [];
      refuse = false;
    });

    Future<void> pump(
      WidgetTester tester, {
      Duration? revertAfter = const Duration(seconds: 2),
      VoidCallback? onRefused,
    }) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            if (refuse) throw PlatformException(code: 'denied');
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.pumpWidget(
        app(
          Center(
            child: CopyButton(
              text: 'shpk1_EXAMPLEKEY-not-a-real-key-0000',
              revertAfter: revertAfter,
              onRefused: onRefused,
            ),
          ),
        ),
      );
    }

    testWidgets('copies, turns to Copied and reverts after two seconds', (
      tester,
    ) async {
      await pump(tester);
      final width = tester.getSize(find.byType(CopyButton)).width;

      await tester.tap(find.byType(CopyButton));
      await tester.pump(const Duration(milliseconds: 150));

      expect(copied, ['shpk1_EXAMPLEKEY-not-a-real-key-0000']);
      expect(find.bySemanticsLabel('Copied'), findsOneWidget);
      // The width is held while the label changes.
      expect(tester.getSize(find.byType(CopyButton)).width, width);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.text('Copied'),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.text('Copied'),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
    });

    testWidgets('on the key screen Copied stays', (tester) async {
      await pump(tester, revertAfter: null);

      await tester.tap(find.byType(CopyButton));
      await tester.pump(const Duration(seconds: 30));

      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.text('Copied'),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        1,
      );
    });

    testWidgets('a clipboard that refuses leaves the button as it was', (
      tester,
    ) async {
      var refused = 0;
      await pump(tester, onRefused: () => refused++);
      refuse = true;

      await tester.tap(find.byType(CopyButton));
      await tester.pump(const Duration(milliseconds: 150));

      expect(refused, 1);
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.ancestor(
                of: find.text('Copied'),
                matching: find.byType(AnimatedOpacity),
              ),
            )
            .opacity,
        0,
      );
    });
  });

  group('AppSearchField', () {
    testWidgets('clears with a button that has a name', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        app(
          AppSearchField(
            controller: controller,
            hint: 'Find a producer',
            onChanged: changes.add,
          ),
        ),
      );
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(tester.getSize(find.byType(TextField)).height, 56);

      await tester.enterText(find.byType(TextField), 'ci');
      await tester.pump();
      expect(changes, ['ci']);
      expect(find.byTooltip('Clear search'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changes.last, '');
      expect(find.byTooltip('Clear search'), findsNothing);
    });
  });
}
