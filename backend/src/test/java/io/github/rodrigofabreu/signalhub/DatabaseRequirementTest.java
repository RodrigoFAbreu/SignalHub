package io.github.rodrigofabreu.signalhub;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Optional;
import org.junit.jupiter.api.Test;

class DatabaseRequirementTest {

  @Test
  void startupFailsWithoutDatabaseUrl() {
    var error =
        assertThrows(
            IllegalStateException.class, () -> DatabaseRequirement.check(Optional.empty()));
    assertTrue(error.getMessage().contains("SIGNALHUB_DB_URL"));
  }

  @Test
  void startupProceedsWithDatabaseUrl() {
    assertDoesNotThrow(
        () -> DatabaseRequirement.check(Optional.of("jdbc:postgresql://localhost/signalhub")));
  }
}
