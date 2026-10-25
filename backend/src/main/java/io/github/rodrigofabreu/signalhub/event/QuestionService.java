package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.api.QuestionState;
import io.github.rodrigofabreu.signalhub.client.ClientIdentity;
import io.github.rodrigofabreu.signalhub.client.ClientKind;
import io.github.rodrigofabreu.signalhub.producer.ProducerAccess;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;
import org.jboss.logging.Logger;

/**
 * Answering an event's question and closing it. The first answer wins, and an answer and the
 * producer's close are one record, so the primary key of {@code event_answers} decides between
 * them. The event row is held against deletion for the transaction, so nothing is recorded for an
 * event that is deleted meanwhile. Logs only IDs.
 */
@ApplicationScoped
class QuestionService {

  private static final Logger LOG = Logger.getLogger(QuestionService.class);

  private final EventRepository events;
  private final EventAnswers answers;
  private final ProducerAccess access;
  private final UserDirectory users;
  private final EventQuestions questions;
  private final QuestionWakeups wakeups;
  private final PushNotices notices;

  QuestionService(
      EventRepository events,
      EventAnswers answers,
      ProducerAccess access,
      UserDirectory users,
      EventQuestions questions,
      QuestionWakeups wakeups,
      PushNotices notices) {
    this.notices = notices;
    this.events = events;
    this.answers = answers;
    this.access = access;
    this.users = users;
    this.questions = questions;
    this.wakeups = wakeups;
  }

  /** What answering did. */
  sealed interface Answering {
    /** Accepted now, or the same person had sent the same answer already. */
    record Accepted(QuestionState.Answer answer) implements Answering {}

    /** Not in the caller's inbox: no such event, deleted, or not subscribed. */
    record NotFound() implements Answering {}

    /** The caller may not answer this producer's questions. */
    record Forbidden() implements Answering {}

    record Invalid(List<ApiError.Violation> violations) implements Answering {
      public Invalid {
        violations = List.copyOf(violations);
      }
    }

    /** Answered or closed already; a null state means the event asks nothing. */
    record Conflict(QuestionState state) implements Answering {}
  }

  /** What closing did. */
  sealed interface Closing {
    /** Closed now, or already closed (by the producer or by time). */
    record Closed(QuestionState state) implements Closing {}

    /** Someone answered first; the state carries that answer. */
    record Answered(QuestionState state) implements Closing {}

    record NotFound() implements Closing {}

    record NoQuestion() implements Closing {}
  }

  /** What the producer's read found. */
  sealed interface Reading {
    record Found(QuestionState state, Instant closesAt) implements Reading {}

    record NotFound() implements Reading {}

    record NoQuestion() implements Reading {}
  }

  @Transactional
  Answering answer(UUID eventId, ClientIdentity caller, AnswerRequest request) {
    if (!answers.lockEvent(eventId)) {
      return new Answering.NotFound();
    }
    var event = events.findById(eventId);
    if (!access.isSubscribed(caller.userId(), event.producerId())) {
      return new Answering.NotFound();
    }
    if (!access.canAnswer(caller.userId(), event.producerId())) {
      return new Answering.Forbidden();
    }
    if (event.ask() == null) {
      return new Answering.Conflict(null);
    }
    var ask = questions.read(event.ask());
    var problems = request.problems(ask);
    if (!problems.isEmpty()) {
      return new Answering.Invalid(problems);
    }
    var choices = request.inOrderOf(ask);
    var now = now();
    var ended = decided(event, caller, request);
    if (ended != null) {
      return ended;
    }
    if (event.askClosesAt() != null && !event.askClosesAt().isAfter(now)) {
      return new Answering.Conflict(EventQuestions.stateOf(event.askClosesAt(), null, now));
    }
    var name = users.find(caller.userId()).orElseThrow().name();
    var via = caller.kind() == ClientKind.BROWSER ? QuestionState.Via.WEB : QuestionState.Via.APP;
    if (answers.insertAnswer(
        eventId, caller.userId(), name, via.name(), choices, request.text(), caller.id(), now)) {
      wakeups.changedAfterCommit(eventId);
      notices.cancelTimed(eventId, now);
      notices.add(eventId, PushNotices.ANSWERED, now, caller.id());
      LOG.infof("User %s answered the question of event %s", caller.userId(), eventId);
      return new Answering.Accepted(
          new QuestionState.Answer(
              choices, request.text(), new QuestionState.By(caller.userId(), name), via, now));
    }
    // Someone else's answer or close was recorded first.
    var raced = decided(event, caller, request);
    return raced != null
        ? raced
        : new Answering.Conflict(EventQuestions.stateOf(event.askClosesAt(), null, Instant.now()));
  }

  /** The outcome if the question already ended: the same answer is accepted again, else refused. */
  private Answering decided(EventEntity event, ClientIdentity caller, AnswerRequest request) {
    var stored = answers.find(event.id());
    if (stored.isEmpty()) {
      return null;
    }
    var ended = stored.get();
    if (!ended.isClose()
        && caller.userId().equals(ended.userId())
        && request.sameAs(ended.choiceIds(), ended.text())) {
      return new Answering.Accepted(EventQuestions.answerOf(ended));
    }
    return new Answering.Conflict(EventQuestions.stateOf(event.askClosesAt(), ended, now()));
  }

  @Transactional
  Closing close(UUID eventId, UUID producerId, String note) {
    if (!answers.lockEvent(eventId)) {
      return new Closing.NotFound();
    }
    var event = events.findById(eventId);
    if (!event.producerId().equals(producerId)) {
      return new Closing.NotFound();
    }
    if (event.ask() == null) {
      return new Closing.NoQuestion();
    }
    var now = now();
    var stored = answers.find(eventId);
    if (stored.isEmpty()
        && (event.askClosesAt() == null || event.askClosesAt().isAfter(now))
        && answers.insertClose(eventId, note, now)) {
      wakeups.changedAfterCommit(eventId);
      notices.cancelTimed(eventId, now);
      notices.add(eventId, PushNotices.CLOSED, now, null);
      LOG.infof("The producer closed the question of event %s", eventId);
      return new Closing.Closed(QuestionState.closed(QuestionState.ClosedBy.PRODUCER, now, note));
    }
    var state =
        EventQuestions.stateOf(event.askClosesAt(), answers.find(eventId).orElse(null), now);
    return state.state() == QuestionState.State.ANSWERED
        ? new Closing.Answered(state)
        : new Closing.Closed(state);
  }

  /** The state of the producer's own event's question, without waiting. */
  @Transactional
  Reading read(UUID eventId, UUID producerId) {
    return events
        .findByIdOptional(eventId)
        .filter(event -> event.producerId().equals(producerId))
        .<Reading>map(
            event ->
                event.ask() == null
                    ? new Reading.NoQuestion()
                    : new Reading.Found(
                        EventQuestions.stateOf(
                            event.askClosesAt(), answers.find(eventId).orElse(null), now()),
                        event.askClosesAt()))
        .orElseGet(Reading.NotFound::new);
  }

  // PostgreSQL stores microseconds; the same clock decides every transition.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
