package io.github.rodrigofabreu.signalhub.event;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
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

  private static AskView ask(boolean multiple, TextStyle style, String... labels) {
    var choices = new java.util.ArrayList<AskView.Choice>();
    for (var i = 0; i < labels.length; i++) {
      choices.add(new AskView.Choice("c" + i, labels[i], "A description that is never shown."));
    }
    return new AskView(
        choices,
        multiple,
        choices.isEmpty() ? AskText.REQUIRED : (style == null ? AskText.NONE : AskText.OPTIONAL),
        style,
        null,
        null);
  }

  @Test
  void upToThreeSingleChoicesAreNamedInTheLine() {
    assertEquals("Tap to answer · Merge", EventPushMessages.hint(ask(false, null, "Merge")));
    assertEquals(
        "Tap to answer · Merge or Hold", EventPushMessages.hint(ask(false, null, "Merge", "Hold")));
    assertEquals(
        "Tap to answer · Restart, Wait or Ignore",
        EventPushMessages.hint(ask(false, null, "Restart", "Wait", "Ignore")));
  }

  @Test
  void moreThanThreeChoicesAreCounted() {
    assertEquals(
        "Tap to answer · 7 choices",
        EventPushMessages.hint(ask(false, null, "a", "b", "c", "d", "e", "f", "g")));
  }

  @Test
  void aMultipleChoiceSaysPickOneOrMoreWhateverTheCount() {
    assertEquals(
        "Tap to answer · pick one or more",
        EventPushMessages.hint(ask(true, null, "Unit tests", "Lint")));
    assertEquals(
        "Tap to answer · pick one or more",
        EventPushMessages.hint(ask(true, null, "a", "b", "c", "d", "e")));
  }

  @Test
  void aTypedQuestionIsJustTapToAnswer() {
    assertEquals("Tap to answer", EventPushMessages.hint(ask(false, null)));
  }

  @Test
  void aLineThatWouldPassEightyCharactersCountsTheChoicesInstead() {
    // "Tap to answer · " is 16 characters; the labels and the joins add 65 more, over by one.
    var a = "a".repeat(20);
    var b = "b".repeat(20);
    var c = "c".repeat(19);
    var over = "Tap to answer · " + a + ", " + b + " or " + c;
    assertEquals(81, over.length());
    assertEquals("Tap to answer · 3 choices", EventPushMessages.hint(ask(false, null, a, b, c)));

    var exactly = "Tap to answer · " + a + ", " + b + " or " + "c".repeat(18);
    assertEquals(80, exactly.length());
    assertEquals(exactly, EventPushMessages.hint(ask(false, null, a, b, "c".repeat(18))));
  }

  @Test
  void theEightyCharactersCountCodePointsNotChars() {
    var label = "🚀".repeat(64); // 64 code points, 128 chars: the line is exactly 80 code points
    var line = EventPushMessages.hint(ask(false, null, label));
    assertEquals("Tap to answer · " + label, line);
    assertEquals(
        "Tap to answer · 1 choice", EventPushMessages.hint(ask(false, null, "🚀".repeat(65))));
  }

  @Test
  void theOtherRowIsNeitherNamedNorCounted() {
    assertEquals(
        EventPushMessages.hint(ask(false, null, "Merge", "Hold")),
        EventPushMessages.hint(ask(false, TextStyle.OTHER, "Merge", "Hold")));
    assertEquals(
        EventPushMessages.hint(ask(true, null, "Merge", "Hold")),
        EventPushMessages.hint(ask(true, TextStyle.OTHER, "Merge", "Hold")));
  }

  @Test
  void aDescriptionIsNeverInTheLine() {
    assertFalse(EventPushMessages.hint(ask(false, null, "Merge", "Hold")).contains("description"));
  }
}
