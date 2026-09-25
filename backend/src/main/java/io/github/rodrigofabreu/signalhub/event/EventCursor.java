package io.github.rodrigofabreu.signalhub.event;

import java.nio.charset.StandardCharsets;
import java.time.DateTimeException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;
import java.util.Optional;
import java.util.UUID;

/**
 * A position in the event listing order ({@code createdAt} descending, then {@code id} descending):
 * the last event of a page. The next page holds the events strictly after it, so events published
 * meanwhile never shift or repeat entries of later pages.
 *
 * <p>Clients treat the encoded form as opaque. It is versioned so that it can change later without
 * misreading cursors issued before the change.
 */
record EventCursor(Instant createdAt, UUID id) {

  private static final String VERSION = "1";
  private static final Base64.Encoder ENCODER = Base64.getUrlEncoder().withoutPadding();
  private static final Base64.Decoder DECODER = Base64.getUrlDecoder();

  String encode() {
    var micros = ChronoUnit.MICROS.between(Instant.EPOCH, createdAt);
    var text = VERSION + ":" + micros + ":" + id;
    return ENCODER.encodeToString(text.getBytes(StandardCharsets.UTF_8));
  }

  /** The cursor, or empty if the text is not a cursor this version issued. */
  static Optional<EventCursor> decode(String encoded) {
    try {
      var parts = new String(DECODER.decode(encoded), StandardCharsets.UTF_8).split(":", -1);
      if (parts.length != 3 || !VERSION.equals(parts[0])) {
        return Optional.empty();
      }
      var createdAt = Instant.EPOCH.plus(Long.parseLong(parts[1]), ChronoUnit.MICROS);
      var id = UUID.fromString(parts[2]);
      if (!id.toString().equals(parts[2])) {
        return Optional.empty();
      }
      return Optional.of(new EventCursor(createdAt, id));
    } catch (IllegalArgumentException | ArithmeticException | DateTimeException e) {
      return Optional.empty();
    }
  }
}
