import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signalhub_client/src/ui/answer_card.dart';
import 'package:signalhub_client/src/ui/event_style.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/phone.dart';
import '../support/screenshot.dart';

/// The answer card of the event screen, in every state of DESIGN.md 10.3.
void main() {
  setUpAll(loadDesignFonts);
  setUp(clearAnswerDrafts);

  Finder byKey(String key) => find.byKey(Key(key));

  /// Scrolls a control of the card into view and taps it.
  Future<void> press(WidgetTester tester, String key) async {
    await tester.ensureVisible(byKey(key));
    await tester.pump();
    await tester.tap(byKey(key));
  }

  /// The text field inside a card's field.
  Finder inner(String key) =>
      find.descendant(of: byKey(key), matching: find.byType(TextField));

  /// The time an answer given at 19:02:11Z shows in, wherever the test runs.
  final answeredAt = formatClock(DateTime.utc(2026, 10, 16, 19, 2, 11));

  final merge = FakeBackend.question(
    choices: [
      ('merge', 'Merge', 'Squash-merge now; CI passed.'),
      ('hold', 'Hold', null),
    ],
    text: 'OPTIONAL',
  );

  /// The app on a phone with one question and its event open.
  Future<AppHarness> open(
    WidgetTester tester, {
    Map<String, Object?>? ask,
    bool canAnswer = true,
    String title = 'Merge R82 into main?',
    void Function(FakeBackend backend)? setUp,
  }) async {
    final app = AppHarness();
    app.backend.publish(
      'e-1',
      title,
      message: 'CI passed on all 3 checks.',
      category: 'ACTION_REQUIRED',
      severity: 'HIGH',
      producer: {'id': 'p-1', 'name': 'ci-pipeline'},
      ask: ask ?? merge,
      canAnswer: canAnswer,
    );
    setUp?.call(app.backend);
    useDesignPhone(tester);
    await app.start(tester);
    await tester.tap(find.text(title));
    await app.settle(tester);
    return app;
  }

  testWidgets('the card sits under the message and says what it asks', (
    tester,
  ) async {
    await open(tester);
    await saveScreenshot(tester, find.byKey(screenshotKey), 'answer-open');

    expect(byKey('answerCard'), findsOneWidget);
    expect(find.text('Your answer'), findsOneWidget);
    expect(
      find.text(
        "Pick one. It goes to ci-pipeline and can't be changed once sent.",
      ),
      findsOneWidget,
    );
    expect(find.text('Merge'), findsOneWidget);
    expect(find.text('Squash-merge now; CI passed.'), findsOneWidget);
    expect(find.text('Hold'), findsOneWidget);
    expect(find.text('Note (optional)'), findsOneWidget);
    expect(find.text('0 / 3000'), findsOneWidget);
    // Under the message, above the rest.
    final message = tester.getTopLeft(find.text('CI passed on all 3 checks.'));
    expect(tester.getTopLeft(byKey('answerCard')).dy, greaterThan(message.dy));
    expect(
      tester.getTopLeft(find.text('Producer')).dy,
      greaterThan(tester.getBottomLeft(byKey('answerCard')).dy),
    );
  });

  testWidgets('choosing sends nothing; Send answer sends, then the result', (
    tester,
  ) async {
    final app = await open(tester);

    await press(tester, 'choice-merge');
    await app.settle(tester);
    expect(app.backend.answers, isEmpty);
    await tester.enterText(inner('noteField'), 'After lunch');
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(app.backend.answers['e-1'], {
      'choices': ['merge'],
      'text': 'After lunch',
    });
    await saveScreenshot(tester, find.byKey(screenshotKey), 'answer-done');
    expect(find.text('You answered · Merge · $answeredAt'), findsOneWidget);
    expect(find.text('Note: After lunch'), findsOneWidget);
    expect(find.text('Sent to ci-pipeline.'), findsOneWidget);
    expect(byKey('sendAnswer'), findsNothing);
    // The list says it in words.
    await tester.pageBack();
    await app.settle(tester);
    expect(find.text('You answered · Merge'), findsOneWidget);
  });

  testWidgets('a note is optional: no note is none', (tester) async {
    final app = await open(tester);

    await press(tester, 'choice-hold');
    await app.settle(tester);
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(app.backend.answers['e-1'], {
      'choices': ['hold'],
    });
  });

  testWidgets('nothing picked says why and sends nothing', (tester) async {
    final app = await open(tester);

    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(find.text('Pick an answer to send.'), findsOneWidget);
    expect(app.backend.answers, isEmpty);
    // The error goes when something is picked.
    await press(tester, 'choice-merge');
    await app.settle(tester);
    expect(find.text('Pick an answer to send.'), findsNothing);
  });

  testWidgets('a multiple choice takes several and needs one', (tester) async {
    final app = await open(
      tester,
      ask: FakeBackend.question(
        choices: [
          ('u', 'Unit tests', 'About 2 minutes.'),
          ('l', 'Lint', null),
          ('t', 'Types', null),
        ],
        multiple: true,
      ),
    );

    expect(
      find.text(
        'Pick one or more. It goes to ci-pipeline and can\'t be '
        'changed once sent.',
      ),
      findsOneWidget,
    );
    expect(find.text('Note (optional)'), findsNothing);
    await press(tester, 'sendAnswer');
    await app.settle(tester);
    expect(find.text('Pick at least one answer.'), findsOneWidget);

    await press(tester, 'choice-u');
    await press(tester, 'choice-l');
    await app.settle(tester);
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(app.backend.answers['e-1'], {
      'choices': ['u', 'l'],
    });
    expect(
      find.text('You answered · Unit tests, Lint · $answeredAt'),
      findsOneWidget,
    );
  });

  testWidgets('a typed question needs text and shows it in quotes', (
    tester,
  ) async {
    final app = await open(tester, ask: FakeBackend.question());

    expect(find.text('Type your answer.'), findsNothing);
    expect(
      find.text(
        "Type your answer. It goes to ci-pipeline and can't be changed once sent.",
      ),
      findsOneWidget,
    );
    await press(tester, 'sendAnswer');
    await app.settle(tester);
    expect(find.text('Type an answer to send.'), findsOneWidget);

    await tester.enterText(inner('noteField'), 'after lunch');
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(app.backend.answers['e-1'], {
      'choices': <String>[],
      'text': 'after lunch',
    });
    expect(find.text('You answered · ‘after lunch’'), findsOneWidget);
    expect(find.text('$answeredAt · Sent to ci-pipeline.'), findsOneWidget);
  });

  testWidgets('a long typed answer goes on its own line, in full', (
    tester,
  ) async {
    final app = await open(tester, ask: FakeBackend.question());
    const text =
        'Answers can now carry a note, and sending twice is harmless to all.';

    await tester.enterText(inner('noteField'), text);
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(find.text('You answered'), findsOneWidget);
    expect(find.text(text), findsOneWidget);
  });

  testWidgets('text past 3000 is flagged, never cut, and not sent', (
    tester,
  ) async {
    final app = await open(tester, ask: FakeBackend.question());

    await tester.enterText(inner('noteField'), 'x' * 3043);
    await app.settle(tester);

    expect(find.text('3043 / 3000'), findsOneWidget);
    expect(
      find.text('Too long: 43 characters over the limit.'),
      findsOneWidget,
    );
    await press(tester, 'sendAnswer');
    await app.settle(tester);
    expect(app.backend.answers, isEmpty);
    expect(
      tester.widget<TextField>(inner('noteField')).controller!.text.length,
      3043,
    );
  });

  group('an Other row', () {
    final port = FakeBackend.question(
      choices: [('a', '8443', 'The usual port.'), ('b', '9443', null)],
      text: 'OPTIONAL',
      textStyle: 'OTHER',
    );

    testWidgets('is last, its field shows once it is picked and has focus', (
      tester,
    ) async {
      final app = await open(tester, ask: port);

      expect(byKey('choice-other'), findsOneWidget);
      expect(byKey('otherField'), findsNothing);
      await press(tester, 'choice-other');
      await app.settle(tester);

      expect(byKey('otherField'), findsOneWidget);
      expect(find.text('Note (optional)'), findsNothing);
      final field = tester.widget<TextField>(inner('otherField'));
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('empty, it says so and sends nothing', (tester) async {
      final app = await open(tester, ask: port);

      await press(tester, 'choice-other');
      await app.settle(tester);
      await press(tester, 'sendAnswer');
      await app.settle(tester);

      expect(find.text('Type your answer for Other.'), findsOneWidget);
      expect(app.backend.answers, isEmpty);
    });

    testWidgets('leaving it keeps its text, and only a shown field is sent', (
      tester,
    ) async {
      final app = await open(tester, ask: port);

      await press(tester, 'choice-other');
      await app.settle(tester);
      await tester.enterText(inner('otherField'), '9000, behind the proxy');
      await press(tester, 'choice-a');
      await app.settle(tester);
      expect(byKey('otherField'), findsNothing);
      await press(tester, 'choice-other');
      await app.settle(tester);
      expect(
        tester.widget<TextField>(inner('otherField')).controller!.text,
        '9000, behind the proxy',
      );

      await press(tester, 'choice-a');
      await app.settle(tester);
      await press(tester, 'sendAnswer');
      await app.settle(tester);
      expect(app.backend.answers['e-1'], {
        'choices': ['a'],
      });
    });

    testWidgets('the answer reads Other, then its text', (tester) async {
      final app = await open(tester, ask: port);

      await press(tester, 'choice-other');
      await app.settle(tester);
      await tester.enterText(inner('otherField'), '9000, behind the proxy');
      await press(tester, 'sendAnswer');
      await app.settle(tester);

      expect(app.backend.answers['e-1'], {
        'choices': <String>[],
        'text': '9000, behind the proxy',
      });
      expect(find.text('You answered · Other · $answeredAt'), findsOneWidget);
      expect(find.text('Other: 9000, behind the proxy'), findsOneWidget);
    });
  });

  testWidgets('someone answered first: the 409 swaps the card to the winner', (
    tester,
  ) async {
    final app = await open(tester);

    await press(tester, 'choice-merge');
    await app.settle(tester);
    app.backend.answerBy('e-1', 'Ana', ['hold']);
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(find.text('Ana answered first: Hold'), findsOneWidget);
    expect(
      find.textContaining(
        "Your answer wasn't sent, and ci-pipeline has Ana's.",
      ),
      findsOneWidget,
    );
    expect(byKey('sendAnswer'), findsNothing);
  });

  testWidgets('closed while choosing: the answer was not sent', (tester) async {
    final app = await open(tester);

    await press(tester, 'choice-merge');
    await app.settle(tester);
    app.backend.close('e-1', by: 'TIME');
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(
      find.text('Closed while you were choosing · nobody can answer it now'),
      findsOneWidget,
    );
    expect(
      find.text("Your answer wasn't sent. ci-pipeline got no answer."),
      findsOneWidget,
    );
  });

  testWidgets('closed by its producer while choosing says who closed it', (
    tester,
  ) async {
    final app = await open(tester);

    await press(tester, 'choice-merge');
    await app.settle(tester);
    app.backend.close('e-1');
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(
      find.text("Your answer wasn't sent. ci-pipeline closed this question."),
      findsOneWidget,
    );
  });

  testWidgets('a send that fails keeps the choice and offers Retry', (
    tester,
  ) async {
    final app = await open(tester);

    await press(tester, 'choice-merge');
    await app.settle(tester);
    await tester.enterText(inner('noteField'), 'kept');
    app.backend.offline = true;
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(find.text('Answer not sent'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester.widget<TextField>(inner('noteField')).controller!.text,
      'kept',
    );
    app.backend.offline = false;
    await tester.tap(find.text('Retry'));
    await app.settle(tester);
    expect(app.backend.answers['e-1'], {
      'choices': ['merge'],
      'text': 'kept',
    });
  });

  testWidgets('a 403 turns the card into the read-only one', (tester) async {
    final app = await open(
      tester,
      ask: FakeBackend.question(
        choices: [('merge', 'Merge', null), ('hold', 'Hold', null)],
        who: [('user-0', 'Rodrigo'), ('user-2', 'Ana')],
      ),
    );

    await press(tester, 'choice-merge');
    await app.settle(tester);
    app.backend
      ..forbidden.add('e-1')
      ..events.first['canAnswer'] = false;
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(byKey('readOnlyCard'), findsOneWidget);
    expect(find.text('Rodrigo or Ana can answer'), findsOneWidget);
    expect(
      find.text(
        "Your answer wasn't sent. You can no longer answer this question.",
      ),
      findsOneWidget,
    );
    expect(byKey('sendAnswer'), findsNothing);
  });

  testWidgets('a person who may only read sees a disabled list', (
    tester,
  ) async {
    await open(
      tester,
      canAnswer: false,
      ask: FakeBackend.question(
        choices: [
          ('merge', 'Merge', 'Squash-merge now; CI passed.'),
          ('hold', 'Hold', null),
        ],
        who: [('user-1', 'Rodrigo'), ('user-2', 'Ana')],
      ),
    );

    expect(byKey('readOnlyCard'), findsOneWidget);
    expect(find.text('Rodrigo or Ana can answer'), findsOneWidget);
    expect(find.text('You can read the question.'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);
    expect(find.text('Squash-merge now; CI passed.'), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsNWidgets(2));
    expect(byKey('sendAnswer'), findsNothing);
    expect(byKey('noteField'), findsNothing);
  });

  testWidgets('nobody can answer it now', (tester) async {
    await open(
      tester,
      canAnswer: false,
      ask: FakeBackend.question(
        choices: [('a', 'A', null), ('b', 'B', null)],
        who: [],
      ),
    );

    expect(find.text('Nobody can answer this now'), findsOneWidget);
  });

  testWidgets('closed with no answer', (tester) async {
    await open(tester, setUp: (backend) => backend.close('e-1', by: 'TIME'));

    expect(find.text('Closed · nobody answered in time'), findsOneWidget);
    expect(find.textContaining('ci-pipeline got no answer.'), findsOneWidget);
    expect(byKey('sendAnswer'), findsNothing);
  });

  testWidgets('closed by its producer, with a short and a long note', (
    tester,
  ) async {
    await open(
      tester,
      setUp: (backend) => backend.close('e-1', note: 'Answered in the session'),
    );
    expect(
      find.text('Closed by ci-pipeline · Answered in the session'),
      findsOneWidget,
    );
    expect(
      find.textContaining('ci-pipeline closed this question on'),
      findsOneWidget,
    );
  });

  testWidgets('a long close note is on its own line, in curly quotes', (
    tester,
  ) async {
    const note = 'Merged by hand after the review in the linked session.';
    await open(tester, setUp: (backend) => backend.close('e-1', note: note));

    expect(find.text('Closed by ci-pipeline'), findsOneWidget);
    expect(find.text('‘$note’'), findsOneWidget);
  });

  testWidgets('someone else answered, read-only, with their name', (
    tester,
  ) async {
    await open(
      tester,
      setUp: (backend) => backend.answerBy('e-1', 'Ana', ['hold']),
    );

    expect(find.text('Ana answered · Hold · 18:55'), findsOneWidget);
    expect(
      find.text('Sent to ci-pipeline. Nobody else can answer now.'),
      findsOneWidget,
    );
  });

  testWidgets('a card left open follows the server when the app resumes', (
    tester,
  ) async {
    final app = await open(tester);
    expect(byKey('sendAnswer'), findsOneWidget);

    app.backend.answerBy('e-1', 'Ana', ['hold']);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await app.settle(tester);

    expect(find.text('Ana answered · Hold · 18:55'), findsOneWidget);
    expect(byKey('sendAnswer'), findsNothing);
  });

  testWidgets('what was typed survives a refresh that changes nothing', (
    tester,
  ) async {
    final app = await open(tester);

    await press(tester, 'choice-merge');
    await tester.enterText(inner('noteField'), 'kept');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await app.settle(tester);

    expect(
      tester.widget<TextField>(inner('noteField')).controller!.text,
      'kept',
    );
  });

  testWidgets('the event deleted meanwhile says it is not in the inbox', (
    tester,
  ) async {
    final app = await open(tester);

    await press(tester, 'choice-merge');
    app.backend.events.clear();
    await press(tester, 'sendAnswer');
    await app.settle(tester);

    expect(
      find.text("This event isn't in your inbox any more"),
      findsOneWidget,
    );
  });

  testWidgets('an event that asks nothing has no card', (tester) async {
    final app = AppHarness();
    app.backend.publish('e-1', 'Plain event');
    useDesignPhone(tester);
    await app.start(tester);
    await tester.tap(find.text('Plain event'));
    await app.settle(tester);

    expect(byKey('answerCard'), findsNothing);
  });

  testWidgets('the event screen has no bottom bar and keeps Mark as unread', (
    tester,
  ) async {
    await open(tester);

    expect(byKey('tab-inbox'), findsNothing);
    expect(find.text('Mark as unread'), findsOneWidget);
  });
}
