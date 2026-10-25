import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/producers.dart';
import '../models/question.dart';
import 'event_style.dart';

/// The words of a question, the same in the inbox and on the event
/// (DESIGN.md 10.3 and 10.4). Curly quotes and the middle dot, as elsewhere.

/// Past this many characters a typed answer, or a producer's note, goes on a
/// line of its own.
const longText = 40;

/// `Rodrigo`, `Rodrigo or Ana`, `Rodrigo, Ana or Rui`: the owner first, as the
/// server lists them.
String namesOf(List<UserName> people) {
  final names = [for (final p in people) p.name];
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} or ${names.last}';
}

/// `Closes at 09:00` today, `Closes 17 Oct at 09:00` another day.
String closesText(DateTime closesAt, DateTime now) {
  final at = closesAt.toLocal();
  final today = now.toLocal();
  final clock = formatClock(at);
  if (at.year == today.year && at.month == today.month && at.day == today.day) {
    return 'Closes at $clock';
  }
  return 'Closes ${_day(at, today)} at $clock';
}

/// When a row says the question closes: `09:00` today, `17 Oct 09:00` on
/// another day.
String closesInRow(DateTime closesAt, DateTime now) {
  final at = closesAt.toLocal();
  final today = now.toLocal();
  final sameDay =
      at.year == today.year && at.month == today.month && at.day == today.day;
  return sameDay ? formatClock(at) : '${_day(at, today)} ${formatClock(at)}';
}

/// `17 Oct`, with the year when it is not this year's.
String _day(DateTime at, DateTime now) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final year = at.year == now.year ? '' : ' ${at.year}';
  return '${at.day} ${months[at.month - 1]}$year';
}

/// `17 Oct at 09:00`, for when a question closed.
String onDayAt(DateTime time, DateTime now) =>
    '${_day(time.toLocal(), now.toLocal())} at ${formatClock(time)}';

/// The words of what an answer picked: the labels of its choices, then
/// `Other` for typed text on an _Other_ row.
class PickedWords {
  const PickedWords({required this.labels, this.typed, this.other, this.note});

  factory PickedWords.of(Ask ask, EventAnswer answer) {
    final labels = [for (final id in answer.choices) ask.labelOf(id)];
    final text = answer.text;
    final other = ask.hasOtherRow && text != null ? text : null;
    if (other != null) labels.add('Other');
    return PickedWords(
      labels: labels.join(', '),
      typed: ask.isTyped ? text : null,
      other: other,
      note: ask.hasNote ? text : null,
    );
  }

  /// `Merge`, `Unit tests, Lint`, `Unit tests, Other`.
  final String labels;

  /// The typed answer of a question without choices.
  final String? typed;

  /// The text of an _Other_ row.
  final String? other;

  /// The note written with the choice.
  final String? note;

  /// What the answer was, in a line: the labels, or the typed text in curly
  /// quotes.
  String get summary => typed != null ? '‘$typed’' : labels;
}

/// The line a question adds to its inbox row, in words so that the state is
/// never only an icon or a colour.
class QuestionLine {
  const QuestionLine(this.icon, this.text, {this.quiet = true});

  final IconData icon;
  final String text;

  /// Grey, not the primary colour of a question waiting for this person.
  final bool quiet;
}

/// The row's line for [event], or `null` for an event that asks nothing.
QuestionLine? questionLine(Event event, {String? myUserId}) {
  final ask = event.ask;
  if (ask == null) return null;
  switch (event.answerState) {
    case AnswerState.answered:
      final answer = event.answer;
      if (answer == null) return null;
      final who = answer.by.id == myUserId ? 'You' : answer.by.name;
      return QuestionLine(
        Icons.check,
        '$who answered · ${PickedWords.of(ask, answer).summary}',
      );
    case AnswerState.closed:
      return event.closedBy == ClosedBy.producer
          ? QuestionLine(Icons.lock_outline, 'Closed by ${event.producer.name}')
          : const QuestionLine(Icons.lock_clock, 'Closed · nobody answered');
    case AnswerState.open || null:
      if (event.canAnswer) {
        final closes = ask.closesAt;
        final text = closes == null
            ? 'To answer'
            : 'To answer · Closes ${closesInRow(closes, DateTime.now())}';
        return QuestionLine(Icons.question_answer_outlined, text, quiet: false);
      }
      return QuestionLine(
        Icons.hourglass_top,
        ask.whoCanAnswer.isEmpty
            ? 'Waiting · nobody can answer'
            : 'Waiting for ${namesOf(ask.whoCanAnswer)}',
      );
  }
}

/// What a card shows in place of the question once it is decided.
class QuestionResult {
  const QuestionResult({
    required this.icon,
    required this.title,
    required this.lines,
    this.mine = false,
    this.filled = true,
    this.textLine,
  });

  final IconData icon;
  final String title;
  final List<String> lines;

  /// The icon is the primary colour: this person answered.
  final bool mine;
  final bool filled;

  /// The index of a line that is the person's or the producer's own text, which
  /// wraps and is never cut.
  final int? textLine;
}

/// Which way this person's own attempt to answer failed, if it did.
enum Attempt { none, answeredFirst, closedWhileChoosing }

/// The result of a decided question, as the card shows it.
QuestionResult? resultOf(
  Event event, {
  String? myUserId,
  Attempt attempt = Attempt.none,
  DateTime? now,
}) {
  final ask = event.ask;
  if (ask == null) return null;
  final producer = event.producer.name;
  final today = now ?? DateTime.now();
  if (event.answerState == AnswerState.answered && event.answer != null) {
    final answer = event.answer!;
    final mine = answer.by.id == myUserId;
    final words = PickedWords.of(ask, answer);
    final time = formatClock(answer.at);
    if (attempt == Attempt.answeredFirst) {
      if (mine) {
        return QuestionResult(
          icon: Icons.info,
          title: 'You already answered: ${words.summary}',
          lines: const ["Your new answer wasn't sent."],
        );
      }
      final possessive = answer.by.name.endsWith('s')
          ? "${answer.by.name}'"
          : "${answer.by.name}'s";
      return QuestionResult(
        icon: Icons.info,
        title: '${answer.by.name} answered first: ${words.summary}',
        lines: [
          "$time. Your answer wasn't sent, and $producer has $possessive.",
        ],
      );
    }
    final who = mine ? 'You' : answer.by.name;
    final sent =
        'Sent to $producer.${mine ? '' : ' Nobody else can answer now.'}';
    final typed = words.typed;
    if (typed != null) {
      if (typed.runes.length <= longText) {
        return QuestionResult(
          icon: Icons.check_circle,
          mine: mine,
          title: '$who answered · ‘$typed’',
          lines: ['$time · $sent'],
        );
      }
      return QuestionResult(
        icon: Icons.check_circle,
        mine: mine,
        title: '$who answered',
        lines: [typed, '$time · $sent'],
        textLine: 0,
      );
    }
    final lines = [
      if (words.other != null) 'Other: ${words.other}',
      if (words.note != null) 'Note: ${words.note}',
      sent,
    ];
    return QuestionResult(
      icon: Icons.check_circle,
      mine: mine,
      title: '$who answered · ${words.labels} · $time',
      lines: lines,
      textLine: words.other != null || words.note != null ? 0 : null,
    );
  }
  if (event.answerState == AnswerState.closed) {
    final byProducer = event.closedBy == ClosedBy.producer;
    final icon = byProducer ? Icons.lock_outline : Icons.lock_clock;
    final closedAt = event.closedAt;
    if (attempt == Attempt.closedWhileChoosing) {
      return QuestionResult(
        icon: icon,
        filled: false,
        title: 'Closed while you were choosing · nobody can answer it now',
        lines: [
          byProducer
              ? "Your answer wasn't sent. $producer closed this question."
              : "Your answer wasn't sent. $producer got no answer.",
        ],
      );
    }
    if (!byProducer) {
      return QuestionResult(
        icon: icon,
        filled: false,
        title: 'Closed · nobody answered in time',
        lines: [
          if (closedAt != null)
            'It closed on ${onDayAt(closedAt, today)}. '
                '$producer got no answer.'
          else
            '$producer got no answer.',
        ],
      );
    }
    final note = event.closeNote;
    final when = closedAt == null
        ? '$producer closed this question.'
        : '$producer closed this question on ${onDayAt(closedAt, today)}.';
    if (note == null) {
      return QuestionResult(
        icon: icon,
        filled: false,
        title: 'Closed by $producer',
        lines: [when],
      );
    }
    if (note.runes.length <= longText) {
      return QuestionResult(
        icon: icon,
        filled: false,
        title: 'Closed by $producer · $note',
        lines: [when],
      );
    }
    return QuestionResult(
      icon: icon,
      filled: false,
      title: 'Closed by $producer',
      lines: ['‘$note’', when],
      textLine: 0,
    );
  }
  return null;
}

/// The title of the read-only card: who can answer, the owner first.
String readOnlyTitle(Ask ask) {
  final people = ask.whoCanAnswer;
  if (people.isEmpty) return 'Nobody can answer this now';
  if (people.length == 1) return '${people.first.name} answers this';
  return '${namesOf(people)} can answer';
}
