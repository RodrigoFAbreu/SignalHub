package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.push.PushMessage;
import java.util.List;
import java.util.Map;

/**
 * What the push for an event says. Built from generic event fields only. A push is a signal to
 * look, so the body is shortened to fit provider payload limits (FCM: 4 KiB) and the client fetches
 * the full event by its ID.
 */
final class EventPushMessages {

  static final int MAX_BODY_LENGTH = 500;

  private EventPushMessages() {}

  static final String TAP_TO_ANSWER = "Tap to answer";
  static final int MAX_HINT_LENGTH = 80;
  private static final int MAX_LISTED_CHOICES = 3;
  private static final String SEPARATOR = " · ";

  static PushMessage of(EventEntity event) {
    return of(event, null);
  }

  /**
   * The push for a device whose user may answer the event's question: the usual text with {@link
   * #hint} as its first line.
   */
  static PushMessage forAnswerer(EventEntity event, AskView ask) {
    return of(event, hint(ask));
  }

  private static PushMessage of(EventEntity event, String hint) {
    var message = event.message() == null ? null : shorten(event.message());
    var body = hint == null ? message : (message == null ? hint : hint + "\n" + message);
    return new PushMessage(
        event.title(),
        body,
        Map.of(
            "eventId", event.id().toString(),
            "category", event.category().name(),
            "severity", event.severity().name()),
        // A retried or later push for the event replaces its card instead of adding a second.
        event.id().toString());
  }

  /**
   * The line that says a push is a question, built from the question alone. Descriptions and the
   * <em>Other</em> row are never in it: that row is neither named nor counted.
   */
  static String hint(AskView ask) {
    var choices = ask.choices();
    if (choices.isEmpty()) {
      return TAP_TO_ANSWER;
    }
    if (ask.multiple()) {
      return TAP_TO_ANSWER + SEPARATOR + "pick one or more";
    }
    if (choices.size() <= MAX_LISTED_CHOICES) {
      var labels = choices.stream().map(AskView.Choice::label).toList();
      var line = TAP_TO_ANSWER + SEPARATOR + joinWithOr(labels);
      if (line.codePointCount(0, line.length()) <= MAX_HINT_LENGTH) {
        return line;
      }
    }
    var count = choices.size();
    return TAP_TO_ANSWER + SEPARATOR + count + (count == 1 ? " choice" : " choices");
  }

  private static String joinWithOr(List<String> labels) {
    if (labels.size() == 1) {
      return labels.get(0);
    }
    var last = labels.size() - 1;
    return String.join(", ", labels.subList(0, last)) + " or " + labels.get(last);
  }

  static String shorten(String text) {
    if (text.codePointCount(0, text.length()) <= MAX_BODY_LENGTH) {
      return text;
    }
    // Cut at a code point, never inside a surrogate pair.
    var end = text.offsetByCodePoints(0, MAX_BODY_LENGTH - 1);
    return text.substring(0, end) + "…";
  }
}
