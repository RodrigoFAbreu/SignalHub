package io.github.rodrigofabreu.signalhub.push;

import java.util.Map;
import java.util.Objects;

/**
 * What a push says, independent of any provider: a short title, an optional body, and string
 * key/value data the client app receives with it (for example the event ID to open). A {@code tag}
 * makes a later push with the same tag replace the earlier one on the device. A data-only message
 * has no title or body and shows nothing: the app acts on its data. Providers translate it into
 * their own format.
 */
public record PushMessage(String title, String body, Map<String, String> data, String tag) {

  public PushMessage {
    if (title == null && body != null) {
      throw new IllegalArgumentException("A push without a title has no body");
    }
    data = Map.copyOf(data);
  }

  public PushMessage(String title, String body, Map<String, String> data) {
    this(Objects.requireNonNull(title, "title"), body, data, null);
  }

  /** A message that shows nothing and only carries data, such as a removal notice. */
  public static PushMessage dataOnly(Map<String, String> data) {
    return new PushMessage(null, null, data, null);
  }

  public boolean isDataOnly() {
    return title == null;
  }
}
