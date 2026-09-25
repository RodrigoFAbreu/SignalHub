package io.github.rodrigofabreu.signalhub.event;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class EventCursorTest {

  @ParameterizedTest
  @ValueSource(
      strings = {
        "2026-09-25T12:03:01.482113Z",
        "1970-01-01T00:00:00Z",
        "1969-12-31T23:59:59.999999Z",
        "0001-01-01T00:00:00Z",
        "9999-12-31T23:59:59.999999Z"
      })
  void roundTripsEveryStorablePosition(String createdAt) {
    var cursor = new EventCursor(Instant.parse(createdAt), UUID.randomUUID());
    assertEquals(Optional.of(cursor), EventCursor.decode(cursor.encode()));
  }

  @Test
  void isUrlSafe() {
    var encoded =
        new EventCursor(Instant.parse("2026-09-25T12:03:01Z"), UUID.randomUUID()).encode();
    assertTrue(encoded.matches("[A-Za-z0-9_-]+"), encoded);
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "",
        "not a cursor",
        "!!!!",
        // "1:abc:<uuid>", "2:0:<uuid>", "1:0", "1:0:not-a-uuid:x" in base64url
        "MTphYmM6MDE5OTdkNWUtOGEzYy03YjFlLTlmMmEtNGM2ZDhlMGYxYTJi",
        "MjowOjAxOTk3ZDVlLThhM2MtN2IxZS05ZjJhLTRjNmQ4ZTBmMWEyYg",
        "MTow",
        "MTowOm5vdC1hLXV1aWQ6eA",
        // "1:99999999999999999999:<uuid>": overflows a long
        "MTo5OTk5OTk5OTk5OTk5OTk5OTk5OTowMTk5N2Q1ZS04YTNjLTdiMWUtOWYyYS00YzZkOGUwZjFhMmI",
      })
  void rejectsAnythingItDidNotIssue(String encoded) {
    assertEquals(Optional.empty(), EventCursor.decode(encoded));
  }
}
