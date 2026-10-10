package io.github.rodrigofabreu.signalhub.client;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import java.time.Instant;
import org.junit.jupiter.api.Test;

class AttemptLimiterTest {

  private static final Instant START = Instant.parse("2026-10-10T12:00:00Z");

  @Test
  void blocksAKeyAfterItsFailuresUntilTheyAgeOut() {
    var limiter = new AttemptLimiter<String>(3, Duration.ofMinutes(10));
    for (var i = 0; i < 3; i++) {
      assertFalse(limiter.blocked("a", START.plusSeconds(i)));
      limiter.fail("a", START.plusSeconds(i));
    }

    assertTrue(limiter.blocked("a", START.plusSeconds(5)));
    assertFalse(limiter.blocked("b", START.plusSeconds(5)));
    // The oldest failure leaves the window first.
    assertFalse(limiter.blocked("a", START.plus(Duration.ofMinutes(10)).plusSeconds(1)));
  }
}
