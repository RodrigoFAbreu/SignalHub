package io.github.rodrigofabreu.signalhub.event;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.rodrigofabreu.signalhub.api.QuestionState;
import io.github.rodrigofabreu.signalhub.producer.ProducerAccess;
import io.github.rodrigofabreu.signalhub.user.NamedUser;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * What an event shows of its question: the question with who can answer it, how it stands, and
 * whether the caller may answer. The state is derived: {@code CLOSED} by time as soon as {@code
 * closesAt} passes, whether or not anything has been written, so every endpoint and filter agrees.
 */
@ApplicationScoped
class EventQuestions {

  private final EventAnswers answers;
  private final ProducerAccess access;
  private final ObjectMapper mapper;

  EventQuestions(EventAnswers answers, ProducerAccess access, ObjectMapper mapper) {
    this.answers = answers;
    this.access = access;
    this.mapper = mapper;
  }

  /** The question as stored text, or null for no question. */
  String store(AskView ask) {
    try {
      return mapper.writeValueAsString(ask);
    } catch (JsonProcessingException e) {
      throw new IllegalStateException("A question could not be written as JSON", e);
    }
  }

  AskView read(String stored) {
    try {
      return mapper.readValue(stored, AskView.class);
    } catch (JsonProcessingException e) {
      throw new IllegalStateException("A stored question could not be read", e);
    }
  }

  /** What a page of events needs to show its questions, loaded in a fixed number of queries. */
  record Context(
      Map<UUID, EventAnswerEntity> answers,
      Map<UUID, List<NamedUser>> who,
      Set<UUID> answerable,
      Instant now) {}

  Context contextFor(Collection<EventEntity> events, Optional<UUID> user) {
    var asking = events.stream().filter(e -> e.ask() != null).toList();
    var now = Instant.now();
    if (asking.isEmpty()) {
      return new Context(Map.of(), Map.of(), Set.of(), now);
    }
    return new Context(
        answers.find(asking.stream().map(EventEntity::id).toList()),
        access.whoCanAnswer(
            asking.stream().map(EventEntity::producerId).collect(Collectors.toSet())),
        user.map(access::answerableProducerIds).orElse(Set.of()),
        now);
  }

  /** The question-related fields of the event's response. */
  record Fields(AskView ask, QuestionState state, boolean canAnswer) {}

  Fields fields(EventEntity event, Context context) {
    if (event.ask() == null) {
      return new Fields(null, null, false);
    }
    var ask =
        read(event.ask())
            .withWhoCanAnswer(context.who().getOrDefault(event.producerId(), List.of()));
    var state = stateOf(event.askClosesAt(), context.answers().get(event.id()), context.now());
    return new Fields(
        ask,
        state,
        state.state() == QuestionState.State.OPEN
            && context.answerable().contains(event.producerId()));
  }

  /** How the question stands at {@code now}, given how it ended, if it did. */
  static QuestionState stateOf(Instant closesAt, EventAnswerEntity ended, Instant now) {
    if (ended != null) {
      return ended.isClose()
          ? QuestionState.closed(QuestionState.ClosedBy.PRODUCER, ended.answeredAt(), ended.note())
          : QuestionState.answered(answerOf(ended));
    }
    if (closesAt != null && !closesAt.isAfter(now)) {
      return QuestionState.closed(QuestionState.ClosedBy.TIME, closesAt, null);
    }
    return QuestionState.open();
  }

  static QuestionState.Answer answerOf(EventAnswerEntity answer) {
    return new QuestionState.Answer(
        answer.choiceIds(),
        answer.text(),
        new QuestionState.By(answer.userId(), answer.userName()),
        QuestionState.Via.valueOf(answer.via()),
        answer.answeredAt());
  }
}
