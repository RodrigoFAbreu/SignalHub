package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.push.PushMessage;
import java.util.Map;

/**
 * What the push for an event says. Built from generic event fields only. A push is a signal to
 * look, so the body is shortened to fit provider payload limits (FCM: 4 KiB) and the client fetches
 * the full event by its ID.
 */
final class EventPushMessages {

  static final int MAX_BODY_LENGTH = 500;

  private EventPushMessages() {}

  static PushMessage of(EventEntity event) {
    return new PushMessage(
        event.title(),
        event.message() == null ? null : shorten(event.message()),
        Map.of(
            "eventId", event.id().toString(),
            "category", event.category().name(),
            "severity", event.severity().name()));
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
