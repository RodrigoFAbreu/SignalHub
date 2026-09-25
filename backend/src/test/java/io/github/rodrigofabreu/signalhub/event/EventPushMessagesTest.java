package io.github.rodrigofabreu.signalhub.event;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class EventPushMessagesTest {

  private static final int MAX = EventPushMessages.MAX_BODY_LENGTH;

  @Test
  void aShortBodyIsKept() {
    var text = "x".repeat(MAX);
    assertSame(text, EventPushMessages.shorten(text));
  }

  @Test
  void aLongBodyIsCutToTheLimitWithAnEllipsis() {
    var shortened = EventPushMessages.shorten("x".repeat(4000));

    assertEquals(MAX, shortened.codePointCount(0, shortened.length()));
    assertTrue(shortened.endsWith("…"), shortened);
  }

  @Test
  void neverSplitsASurrogatePair() {
    var emoji = "🚀"; // one code point, two chars
    var shortened = EventPushMessages.shorten(emoji.repeat(MAX + 1));

    assertEquals(MAX, shortened.codePointCount(0, shortened.length()));
    assertEquals(emoji.repeat(MAX - 1) + "…", shortened);
  }
}
