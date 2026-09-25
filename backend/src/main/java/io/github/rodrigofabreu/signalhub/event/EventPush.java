package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.client.PushPreferences;
import io.github.rodrigofabreu.signalhub.push.PushMessage;
import java.util.UUID;

/** The push for one event, with the generic fields that push preferences are matched against. */
record EventPush(Category category, Severity severity, UUID producerId, PushMessage message) {

  static EventPush of(EventEntity event) {
    return new EventPush(
        event.category(), event.severity(), event.producerId(), EventPushMessages.of(event));
  }

  boolean allowedBy(PushPreferences preferences) {
    return preferences.allow(category, severity, producerId);
  }
}
