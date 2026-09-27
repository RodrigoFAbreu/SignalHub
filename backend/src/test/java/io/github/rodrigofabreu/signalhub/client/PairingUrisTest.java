package io.github.rodrigofabreu.signalhub.client;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;
import org.junit.jupiter.params.provider.ValueSource;

class PairingUrisTest {

  private static final String CODE = "shpc1_AAAAAAAAAAAAAAAAAAAAAA";

  @Test
  void theUriHoldsTheServerAndTheCode() {
    var uris = new PairingUris(Optional.of("https://signalhub.example.com/"));

    assertEquals(
        Optional.of("signalhub://pair?server=https%3A%2F%2Fsignalhub.example.com&code=" + CODE),
        uris.of(CODE));
  }

  @ParameterizedTest
  @ValueSource(strings = {"", "  "})
  void withoutAPublicUrlThereIsNoUri(String unset) {
    assertEquals(Optional.empty(), new PairingUris(Optional.of(unset)).of(CODE));
    assertEquals(Optional.empty(), new PairingUris(Optional.empty()).of(CODE));
  }

  @ParameterizedTest
  @CsvSource({
    "https://signalhub.example.com, https://signalhub.example.com",
    "https://signalhub.example.com/, https://signalhub.example.com",
    "http://192.168.1.20:8080, http://192.168.1.20:8080",
    "https://example.com/signalhub/, https://example.com/signalhub",
  })
  void theServerAddressHasNoTrailingSlash(String configured, String address) {
    assertEquals(address, PairingUris.serverAddress(configured));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "signalhub.example.com",
        "ftp://signalhub.example.com",
        "https://",
        "https://user:secret@signalhub.example.com",
        "https://signalhub.example.com/?x=1",
        "https://signalhub.example.com/#top",
        "https://signal hub.example.com",
      })
  void aMalformedPublicUrlStopsStartup(String configured) {
    var error =
        assertThrows(IllegalStateException.class, () -> new PairingUris(Optional.of(configured)));
    assertTrue(error.getMessage().startsWith("SIGNALHUB_PUBLIC_URL must be"));
  }

  @Test
  void codesAreRandomAndWellFormed() {
    var first = PairingCodes.generate();
    var second = PairingCodes.generate();

    assertTrue(PairingCodes.isWellFormed(first), first);
    assertTrue(first.length() == 28 && !first.equals(second));
    assertTrue(!PairingCodes.isWellFormed(first + "A"));
    assertTrue(!PairingCodes.isWellFormed("shck1_" + first.substring(6)));
  }
}
