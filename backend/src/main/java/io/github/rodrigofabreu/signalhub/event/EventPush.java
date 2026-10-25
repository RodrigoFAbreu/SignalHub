package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.QuestionState;
import io.github.rodrigofabreu.signalhub.client.PushPreferences;
import io.github.rodrigofabreu.signalhub.push.PushMessage;
import java.util.Optional;
import java.util.UUID;

/** The push for one event, with the generic fields that push preferences are matched against. */
record EventPush(
    Category category,
    Severity severity,
    UUID producerId,
    PushMessage message,
    PushMessage answererMessage,
    QuestionState.State question) {

  /** The push for the event, whose question (if it asks one) stands as {@code question}. */
  static EventPush of(EventEntity event, AskView ask, QuestionState.State question) {
    return new EventPush(
        event.category(),
        event.severity(),
        event.producerId(),
        EventPushMessages.of(event),
        ask == null ? null : EventPushMessages.forAnswerer(event, ask),
        question);
  }

  /**
   * What the push says to a user: for a question that is still open and that the user may answer,
   * the text with the "Tap to answer" line first; the event's usual text otherwise.
   */
  PushMessage messageFor(boolean mayAnswer) {
    return mayAnswer && answererMessage != null && question == QuestionState.State.OPEN
        ? answererMessage
        : message;
  }

  /**
   * Why the push is no longer worth sending: its question was answered or closed, so a card for it
   * would only be removed again. Empty while the question is open, or the event asks nothing.
   */
  Optional<String> questionEnded() {
    if (question == QuestionState.State.ANSWERED) {
      return Optional.of("question answered");
    }
    return question == QuestionState.State.CLOSED
        ? Optional.of("question closed")
        : Optional.empty();
  }

  /** Why the push is not sent to a client: its question ended, or its preferences exclude it. */
  Optional<String> skippedFor(PushPreferences preferences) {
    return questionEnded().or(() -> exclusionBy(preferences));
  }

  /** The preference that keeps this push from the client; empty if it is pushed. */
  Optional<String> exclusionBy(PushPreferences preferences) {
    return preferences.exclusion(category, severity, producerId);
  }
}
