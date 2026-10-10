package io.github.rodrigofabreu.signalhub.client;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import org.junit.jupiter.api.Test;

class WebSignInCodesTest {

  @Test
  void aTypedCodeHasSixCharactersWithoutLookAlikes() {
    for (var i = 0; i < 200; i++) {
      assertTrue(WebSignInCodes.typed().matches("[A-HJKMNP-Z2-9]{6}"));
    }
    assertEquals("K7Q-4MX", WebSignInCodes.display("K7Q4MX"));
  }

  @Test
  void whatAPersonTypesIsNormalisedAndAScanCodeIsKept() {
    assertEquals("K7Q4MX", WebSignInCodes.normalise(" k7q-4mx "));
    assertEquals("K7Q4MX", WebSignInCodes.normalise("K7Q 4MX"));
    var scan = WebSignInCodes.scan();
    assertEquals(scan, WebSignInCodes.normalise(scan));
  }

  @Test
  void aPollSecretIsRecognisedByItsForm() {
    assertTrue(WebSignInCodes.isWellFormedPoll(WebSignInCodes.poll()));
    assertFalse(WebSignInCodes.isWellFormedPoll(WebSignInCodes.scan()));
    assertFalse(WebSignInCodes.isWellFormedPoll("x"));
  }
}
