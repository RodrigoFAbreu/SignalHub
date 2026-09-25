package io.github.rodrigofabreu.signalhub.push;

import java.util.Map;
import java.util.Objects;

/**
 * What a push says, independent of any provider: a short title, an optional body, and string
 * key/value data the client app receives with it (for example the event ID to open). Providers
 * translate it into their own format.
 */
public record PushMessage(String title, String body, Map<String, String> data) {

  public PushMessage {
    Objects.requireNonNull(title, "title");
    data = Map.copyOf(data);
  }
}
