package io.github.rodrigofabreu.signalhub.client;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/** Which events push preferences let through. */
class PushPreferencesTest {

  private static final UUID PRODUCER = UUID.fromString("01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b");
  private static final UUID OTHER = UUID.fromString("01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2c");

  @Test
  void theDefaultPushesEveryEvent() {
    for (var category : Category.values()) {
      for (var severity : Severity.values()) {
        assertTrue(PushPreferences.DEFAULT.allow(category, severity, PRODUCER));
      }
    }
  }

  @Test
  void pausedPushesNothing() {
    var paused = new PushPreferences(false, Severity.LOW, List.of(), List.of());

    assertFalse(paused.allow(Category.ACTION_REQUIRED, Severity.CRITICAL, PRODUCER));
  }

  @Test
  void theMinimumSeverityIsInclusive() {
    var high = new PushPreferences(true, Severity.HIGH, List.of(), List.of());

    assertFalse(high.allow(Category.INFO, Severity.LOW, PRODUCER));
    assertFalse(high.allow(Category.INFO, Severity.NORMAL, PRODUCER));
    assertTrue(high.allow(Category.INFO, Severity.HIGH, PRODUCER));
    assertTrue(high.allow(Category.INFO, Severity.CRITICAL, PRODUCER));
  }

  @Test
  void mutedCategoriesAndProducersAreNotPushed() {
    var muted = new PushPreferences(true, Severity.LOW, List.of(Category.INFO), List.of(OTHER));

    assertFalse(muted.allow(Category.INFO, Severity.CRITICAL, PRODUCER));
    assertFalse(muted.allow(Category.BLOCKED, Severity.CRITICAL, OTHER));
    assertTrue(muted.allow(Category.BLOCKED, Severity.LOW, PRODUCER));
  }

  @Test
  void mutedListsAreSortedWithoutDuplicates() {
    var preferences =
        new PushPreferences(
            true,
            Severity.LOW,
            List.of(Category.INFO, Category.BLOCKED, Category.INFO),
            List.of(OTHER, PRODUCER, OTHER));

    assertEquals(List.of(Category.BLOCKED, Category.INFO), preferences.mutedCategories());
    assertEquals(List.of(PRODUCER, OTHER), preferences.mutedProducerIds());
  }
}
