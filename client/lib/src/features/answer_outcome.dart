import '../models/event.dart';
import '../models/question.dart';

/// What came of sending an answer. The card shows each in its own words
/// (DESIGN.md 10.3): it is never only an error.
sealed class AnswerOutcome {
  const AnswerOutcome();
}

/// The answer was accepted: the question is answered, by this person.
class AnswerAccepted extends AnswerOutcome {
  const AnswerAccepted(this.state);

  final QuestionState state;
}

/// Someone answered first, or the question closed: [state] says who answered
/// what, or who closed it. The choice and the note are dropped.
class AnswerRefused extends AnswerOutcome {
  const AnswerRefused(this.state);

  final QuestionState state;
}

/// The server said this person may not answer; [event] is the event read
/// again, whose `canAnswer` says whether that is still so.
class AnswerNotAllowed extends AnswerOutcome {
  const AnswerNotAllowed(this.event);

  final Event event;
}

/// The event is not in this person's inbox any more.
class AnswerGone extends AnswerOutcome {
  const AnswerGone();
}

/// Nothing was sent or the server could not take it: the choice and the note
/// are kept, and the card offers to try again.
class AnswerFailed extends AnswerOutcome {
  const AnswerFailed(this.message);

  final String message;
}
