import 'json.dart';
import 'producers.dart';

/// Where a question stands (`answerState`): open until it is answered or
/// closes, and then final. An unrecognised value is read as [open] so the
/// card never offers more than the server allows: a `409` says the rest.
enum AnswerState {
  open('OPEN'),
  answered('ANSWERED'),
  closed('CLOSED');

  const AnswerState(this.wireName);

  final String wireName;

  static AnswerState? parse(String? value) {
    if (value == null) return null;
    return values.firstWhere((s) => s.wireName == value, orElse: () => open);
  }
}

/// Who or what closed a question (`closedBy`): its producer, or its time.
enum ClosedBy {
  producer('PRODUCER'),
  time('TIME');

  const ClosedBy(this.wireName);

  final String wireName;

  static ClosedBy? parse(String? value) {
    if (value == null) return null;
    return values.firstWhere((c) => c.wireName == value, orElse: () => time);
  }
}

/// Whether a question takes text (`ask.text`): none, optional or required.
enum AskText {
  none('NONE'),
  optional('OPTIONAL'),
  required('REQUIRED');

  const AskText(this.wireName);

  final String wireName;

  static AskText parse(String value) =>
      values.firstWhere((t) => t.wireName == value, orElse: () => none);
}

/// What the typed text of a question is (`ask.textStyle`): a note written
/// with the choice, or an _Other_ row picked instead of a choice.
enum AskTextStyle {
  note('NOTE'),
  other('OTHER');

  const AskTextStyle(this.wireName);

  final String wireName;

  static AskTextStyle? parse(String? value) {
    if (value == null) return null;
    return values.firstWhere((t) => t.wireName == value, orElse: () => note);
  }
}

/// One choice of a question. SignalHub never interprets it: the label and the
/// description are shown as the producer sent them.
class AskChoice {
  const AskChoice({required this.id, required this.label, this.description});

  factory AskChoice.fromJson(Map<String, Object?> json) => AskChoice(
    id: json.string('id'),
    label: json.string('label'),
    description: json.optionalString('description'),
  );

  final String id;
  final String label;

  /// Plain text under the label; `null` when there is none.
  final String? description;
}

/// The question of an event (`ask`): choices to pick from, typed text, or
/// both.
class Ask {
  const Ask({
    required this.choices,
    required this.text,
    this.multiple = false,
    this.textStyle,
    this.closesAt,
    this.whoCanAnswer = const [],
  });

  factory Ask.fromJson(Map<String, Object?> json) => Ask(
    choices: json
        .list('choices')
        .map((c) => AskChoice.fromJson(asObject(c, 'choices[]')))
        .toList(growable: false),
    multiple: json.optionalBoolean('multiple') ?? false,
    text: AskText.parse(json.string('text')),
    textStyle: AskTextStyle.parse(json.optionalString('textStyle')),
    closesAt: json.optionalTimestamp('closesAt'),
    whoCanAnswer: (json['whoCanAnswer'] as List<Object?>? ?? const [])
        .map((u) => UserName.fromJson(asObject(u, 'whoCanAnswer[]')))
        .toList(growable: false),
  );

  final List<AskChoice> choices;
  final bool multiple;
  final AskText text;
  final AskTextStyle? textStyle;

  /// When the question closes by itself; `null` if it does not.
  final DateTime? closesAt;

  /// Who may answer, the owner first.
  final List<UserName> whoCanAnswer;

  /// A question without choices: the answer is typed.
  bool get isTyped => choices.isEmpty;

  /// Whether the last row is _Other_.
  bool get hasOtherRow =>
      !isTyped && text != AskText.none && textStyle == AskTextStyle.other;

  /// Whether a note is written with the chosen choice.
  bool get hasNote => !isTyped && text != AskText.none && !hasOtherRow;

  /// The label of the choice with [id]; the id itself when unknown.
  String labelOf(String id) =>
      choices.where((c) => c.id == id).firstOrNull?.label ?? id;
}

/// The answer given to a question (`answer`): the choices picked, the typed
/// text, who gave it, and where.
class EventAnswer {
  const EventAnswer({
    required this.choices,
    required this.by,
    required this.at,
    this.text,
    this.via,
  });

  factory EventAnswer.fromJson(Map<String, Object?> json) => EventAnswer(
    choices: json.strings('choices'),
    text: json.optionalString('text'),
    by: UserName.fromJson(json.object('by')),
    via: json.optionalString('via'),
    at: json.timestamp('at'),
  );

  /// The ids of the choices, in the question's order.
  final List<String> choices;
  final String? text;

  /// The name stored with the answer, even if the person is renamed later.
  final UserName by;

  /// `APP` or `WEB`.
  final String? via;
  final DateTime at;
}

/// The state of a question as a `409` carries it, and as the producer reads
/// it: what a card needs to show who answered or who closed it.
class QuestionState {
  const QuestionState({
    required this.state,
    this.answer,
    this.closedBy,
    this.closedAt,
    this.closeNote,
  });

  factory QuestionState.fromJson(Map<String, Object?> json) => QuestionState(
    state: AnswerState.parse(json.string('state')) ?? AnswerState.open,
    answer: json.optionalObjectAs('answer', EventAnswer.fromJson),
    closedBy: ClosedBy.parse(json.optionalString('closedBy')),
    closedAt: json.optionalTimestamp('closedAt'),
    closeNote: json.optionalString('closeNote'),
  );

  final AnswerState state;
  final EventAnswer? answer;
  final ClosedBy? closedBy;
  final DateTime? closedAt;
  final String? closeNote;
}

/// The unread count and the number of open questions this person may answer
/// (`GET /api/v1/events/unread-count`).
class EventCounts {
  const EventCounts({required this.unread, this.toAnswer = 0});

  factory EventCounts.fromJson(Map<String, Object?> json) => EventCounts(
    unread: json.integer('unread'),
    toAnswer: json.optionalInteger('toAnswer') ?? 0,
  );

  final int unread;
  final int toAnswer;
}
