package io.github.rodrigofabreu.signalhub.producer;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Locale;
import java.util.Optional;
import org.junit.jupiter.api.Test;

class AdminTokenTest {

  private static final String TOKEN = "a".repeat(AdminToken.MIN_LENGTH);

  @Test
  void shortTokenStopsStartup() {
    var error =
        assertThrows(
            IllegalStateException.class,
            () -> new AdminToken(Optional.of("a".repeat(AdminToken.MIN_LENGTH - 1))));
    assertTrue(error.getMessage().contains("SIGNALHUB_ADMIN_TOKEN"));
  }

  @Test
  void noTokenDisablesTheManagementApi() {
    var token = assertDoesNotThrow(() -> new AdminToken(Optional.empty()));
    assertFalse(token.enabled());
    assertFalse(token.matches(""));
    assertFalse(token.matches(TOKEN));
  }

  @Test
  void onlyTheExactTokenMatches() {
    var token = new AdminToken(Optional.of(TOKEN));
    assertTrue(token.enabled());
    assertTrue(token.matches(TOKEN));
    assertFalse(token.matches(TOKEN + "a"));
    assertFalse(token.matches(TOKEN.substring(1)));
    assertFalse(token.matches(TOKEN.toUpperCase(Locale.ROOT)));
    assertFalse(token.matches(""));
  }
}
