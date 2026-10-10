package io.github.rodrigofabreu.signalhub.client;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class BrowserNamesTest {

  @ParameterizedTest
  @CsvSource(
      delimiter = '|',
      value = {
        "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0|Firefox on Linux",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)"
            + " Chrome/129.0.0.0 Safari/537.36|Chrome on Windows",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko)"
            + " Chrome/129.0.0.0 Safari/537.36 Edg/129.0.0.0|Edge on Windows",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)"
            + " Version/17.6 Safari/605.1.15|Safari on macOS",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like"
            + " Gecko) Version/17.6 Mobile/15E148 Safari/604.1|Safari on iPhone",
        "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko)"
            + " Chrome/129.0.0.0 Mobile Safari/537.36|Chrome on Android",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0"
            + " Safari/537.36 OPR/114.0.0.0|Opera on Linux",
        "curl/8.5.0|Browser",
        "Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) Gecko|Browser on ChromeOS",
      })
  void namesTheBrowserAndTheSystem(String userAgent, String name) {
    assertEquals(name, BrowserNames.of(userAgent));
  }

  @Test
  void anAbsentUserAgentIsJustABrowser() {
    assertEquals("Browser", BrowserNames.of(null));
    assertEquals("Browser", BrowserNames.of("  "));
  }
}
