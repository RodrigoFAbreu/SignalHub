package io.github.rodrigofabreu.signalhub.event;

import static org.junit.jupiter.api.Assertions.assertEquals;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import java.time.Instant;
import org.junit.jupiter.api.Test;

/** Without a retention period, the default, events are kept forever. */
@QuarkusTest
class EventRetentionDisabledTest {

  @Inject EventRetention retention;

  @Test
  void nothingIsDeleted() {
    assertEquals(0, retention.deleteExpired(Instant.parse("9999-01-01T00:00:00Z")));
  }
}
