package io.github.rodrigofabreu.signalhub.client;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.Locale;
import java.util.regex.Pattern;

/**
 * The secrets of a web sign-in. The page keeps a long {@code poll} secret to itself and collects
 * the session with it. It shows two codes a device can look the sign-in up by: a short {@code
 * typed} code (six characters, shown as {@code K7Q-4MX}) for a person to type, and a long {@code
 * scan} code in the QR code. Only SHA-256 of each is stored.
 *
 * <p>The typed code has about 30 bits, so it is safe only because it lives three minutes, only an
 * authenticated device may try it, and wrong tries are bounded ({@link WebSignInService}). The
 * alphabet leaves out the characters people mistake for each other.
 */
final class WebSignInCodes {

  static final String SCAN_PREFIX = "shsc1_";
  static final String POLL_PREFIX = "shsp1_";

  private static final String ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  private static final int TYPED_LENGTH = 6;
  private static final Pattern SCAN_FORMAT =
      Pattern.compile(Pattern.quote(SCAN_PREFIX) + "[A-Za-z0-9_-]{22}");
  private static final Pattern POLL_FORMAT =
      Pattern.compile(Pattern.quote(POLL_PREFIX) + "[A-Za-z0-9_-]{43}");
  private static final SecureRandom RANDOM = new SecureRandom();

  private WebSignInCodes() {}

  /** Six characters, normalised: {@code K7Q4MX}. */
  static String typed() {
    var code = new StringBuilder();
    for (var i = 0; i < TYPED_LENGTH; i++) {
      code.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
    }
    return code.toString();
  }

  /** The typed code as people read it: {@code K7Q-4MX}. */
  static String display(String typed) {
    return typed.substring(0, 3) + "-" + typed.substring(3);
  }

  static String scan() {
    return SCAN_PREFIX + random(16);
  }

  static String poll() {
    return POLL_PREFIX + random(32);
  }

  static boolean isWellFormedPoll(String secret) {
    return POLL_FORMAT.matcher(secret).matches();
  }

  /**
   * What a person typed or a scan gave, as it is hashed: a scan code as it is, anything else
   * upper-cased without spaces and dashes. Says nothing about whether the code exists.
   */
  static String normalise(String entered) {
    var trimmed = entered.strip();
    if (SCAN_FORMAT.matcher(trimmed).matches()) {
      return trimmed;
    }
    return trimmed.replaceAll("[\\s-]", "").toUpperCase(Locale.ROOT);
  }

  private static String random(int bytes) {
    var secret = new byte[bytes];
    RANDOM.nextBytes(secret);
    return Base64.getUrlEncoder().withoutPadding().encodeToString(secret);
  }
}
