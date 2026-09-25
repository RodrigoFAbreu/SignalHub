package io.github.rodrigofabreu.signalhub.producer;

import static org.junit.jupiter.api.Assertions.assertEquals;

import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullSource;
import org.junit.jupiter.params.provider.ValueSource;

class BearerTokenTest {

  @ParameterizedTest
  @ValueSource(strings = {"Bearer abc", "bearer abc", "BEARER abc"})
  void readsTheTokenWhateverTheSchemeCase(String header) {
    assertEquals(Optional.of("abc"), BearerToken.from(header));
  }

  @ParameterizedTest
  @NullSource
  @ValueSource(strings = {"", "Bearer", "Bearer ", "Bearerabc", "Basic abc", "abc", "Bearer\tabc"})
  void rejectsAnythingElse(String header) {
    assertEquals(Optional.empty(), BearerToken.from(header));
  }

  @Test
  void leavesTheTokenForTheCallerToCheck() {
    // Extra spaces or values end up in the token, which then fails the key format check.
    assertEquals(Optional.of(" abc"), BearerToken.from("Bearer  abc"));
  }
}
