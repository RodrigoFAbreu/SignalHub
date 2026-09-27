package io.github.rodrigofabreu.signalhub.client;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.regex.Pattern;

/**
 * Pairing codes: {@code shpc1_<secret>} ("SignalHub pairing code", version 1), a prefix distinct
 * from client and producer keys so a scanner can tell them apart. The secret is 16 bytes from
 * {@link SecureRandom}, base64url without padding (22 chars): 128 bits make guessing infeasible for
 * a code that lives minutes, and keep the pairing QR code small. Only SHA-256 of the complete code
 * is stored; being random, the code needs no ID to find its record.
 */
final class PairingCodes {

  static final String PREFIX = "shpc1_";

  private static final int SECRET_BYTES = 16;
  private static final Pattern FORMAT =
      Pattern.compile(Pattern.quote(PREFIX) + "[A-Za-z0-9_-]{22}");
  private static final SecureRandom RANDOM = new SecureRandom();

  private PairingCodes() {}

  /** A new random pairing code. */
  static String generate() {
    var secret = new byte[SECRET_BYTES];
    RANDOM.nextBytes(secret);
    return PREFIX + Base64.getUrlEncoder().withoutPadding().encodeToString(secret);
  }

  /** Whether this has the form of a pairing code; says nothing about whether one exists. */
  static boolean isWellFormed(String code) {
    return FORMAT.matcher(code).matches();
  }
}
