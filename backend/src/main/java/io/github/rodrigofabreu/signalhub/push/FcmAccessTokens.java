package io.github.rodrigofabreu.signalhub.push;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.Signature;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;

/**
 * OAuth 2.0 access tokens for the FCM API, obtained with the service account's key (the JWT bearer
 * grant, RFC 7523) and cached until shortly before they expire.
 */
final class FcmAccessTokens {

  static final String SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

  private static final Duration ASSERTION_LIFETIME = Duration.ofHours(1);
  // Renew early so a token never expires between being handed out and being used.
  private static final Duration RENEWAL_MARGIN = Duration.ofMinutes(5);
  private static final Duration TIMEOUT = Duration.ofSeconds(10);

  /** Getting a token failed; {@link #outcome} classifies the failure for the send it blocked. */
  static final class Failure extends Exception {
    private static final long serialVersionUID = 1L;

    private final transient PushOutcome outcome;

    Failure(PushOutcome.Status status, String detail) {
      super(detail, null, false, false);
      this.outcome = new PushOutcome(status, detail);
    }

    PushOutcome outcome() {
      return outcome;
    }
  }

  private final FcmCredentials credentials;
  private final HttpClient http;
  private final Clock clock;
  private final ObjectMapper json = new ObjectMapper();

  private String token;
  private Instant renewAt = Instant.MIN;

  FcmAccessTokens(FcmCredentials credentials, HttpClient http, Clock clock) {
    this.credentials = credentials;
    this.http = http;
    this.clock = clock;
  }

  synchronized String get() throws Failure, IOException, InterruptedException {
    if (token == null || !clock.instant().isBefore(renewAt)) {
      fetch();
    }
    return token;
  }

  /** Forgets the cached token, e.g. after FCM rejected it. */
  synchronized void invalidate() {
    token = null;
  }

  private void fetch() throws Failure, IOException, InterruptedException {
    var now = clock.instant();
    var form =
        "grant_type="
            + URLEncoder.encode(
                "urn:ietf:params:oauth:grant-type:jwt-bearer", StandardCharsets.UTF_8)
            + "&assertion="
            + assertion(now);
    var request =
        HttpRequest.newBuilder(credentials.tokenUri())
            .timeout(TIMEOUT)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .POST(HttpRequest.BodyPublishers.ofString(form))
            .build();
    var response = http.send(request, HttpResponse.BodyHandlers.ofString());
    if (response.statusCode() != 200) {
      // 4xx: the key or account is rejected, a configuration problem. Otherwise try again later.
      var status =
          response.statusCode() >= 400
                  && response.statusCode() < 500
                  && response.statusCode() != 429
              ? PushOutcome.Status.PERMANENT_FAILURE
              : PushOutcome.Status.TRANSIENT_FAILURE;
      throw new Failure(status, "access token request failed: HTTP " + response.statusCode());
    }
    JsonNode body;
    try {
      body = json.readTree(response.body());
    } catch (IOException e) {
      throw new Failure(PushOutcome.Status.TRANSIENT_FAILURE, "access token response is not JSON");
    }
    var accessToken = body == null ? null : body.path("access_token");
    if (accessToken == null || !accessToken.isTextual() || accessToken.asText().isEmpty()) {
      throw new Failure(
          PushOutcome.Status.TRANSIENT_FAILURE, "access token response has no access_token");
    }
    var lifetime = Duration.ofSeconds(Math.max(0, body.path("expires_in").asLong(0)));
    token = accessToken.asText();
    renewAt = now.plus(lifetime).minus(RENEWAL_MARGIN);
  }

  private String assertion(Instant now) throws IOException {
    var header = Map.of("alg", "RS256", "typ", "JWT");
    var claims =
        Map.of(
            "iss", credentials.clientEmail(),
            "scope", SCOPE,
            "aud", credentials.tokenUri().toString(),
            "iat", now.getEpochSecond(),
            "exp", now.plus(ASSERTION_LIFETIME).getEpochSecond());
    var signingInput =
        base64Url(json.writeValueAsBytes(header)) + "." + base64Url(json.writeValueAsBytes(claims));
    try {
      var signature = Signature.getInstance("SHA256withRSA");
      signature.initSign(credentials.privateKey());
      signature.update(signingInput.getBytes(StandardCharsets.US_ASCII));
      return signingInput + "." + base64Url(signature.sign());
    } catch (GeneralSecurityException e) {
      // The key was validated at startup, so this is a JDK problem, not a bad key.
      throw new IllegalStateException("Cannot sign the FCM access token request", e);
    }
  }

  private static String base64Url(byte[] bytes) {
    return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
  }
}
