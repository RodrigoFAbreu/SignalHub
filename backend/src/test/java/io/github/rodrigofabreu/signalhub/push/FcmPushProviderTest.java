package io.github.rodrigofabreu.signalhub.push;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.net.URI;
import java.net.http.HttpClient;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Map;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

/** The FCM provider against {@link FakeFcm}: request format, access tokens, error mapping. */
class FcmPushProviderTest {

  private static final String TOKEN = "device-token-0123456789";
  private static final PushMessage MESSAGE =
      new PushMessage("Build failed", "3 tests failed", Map.of("eventId", "e-1"));

  private static FakeFcm fcm;

  private MutableClock clock;
  private FcmPushProvider provider;

  @BeforeAll
  static void startFake() {
    fcm = new FakeFcm();
  }

  @AfterAll
  static void stopFake() {
    fcm.close();
  }

  @BeforeEach
  void newProvider() {
    fcm.reset();
    clock = new MutableClock(Instant.parse("2026-01-01T00:00:00Z"));
    provider =
        new FcmPushProvider(fcm.credentials(), fcm.apiUrl(), HttpClient.newHttpClient(), clock);
  }

  @Test
  void isNamedFcm() {
    assertEquals("fcm", provider.name());
  }

  @Test
  void sendsANotificationMessageToTheProjectsSendEndpoint() {
    assertEquals(PushOutcome.delivered(), provider.send(TOKEN, MESSAGE));

    var send = fcm.sends().get(0);
    assertEquals("/v1/projects/" + FakeFcm.PROJECT + "/messages:send", send.path());
    assertTrue(send.authorization().startsWith("Bearer access-"), send.authorization());
    var message = send.body().path("message");
    assertEquals(TOKEN, message.path("token").asText());
    assertEquals("Build failed", message.path("notification").path("title").asText());
    assertEquals("3 tests failed", message.path("notification").path("body").asText());
    assertEquals("e-1", message.path("data").path("eventId").asText());
  }

  @Test
  void leavesOutAnAbsentBodyAndEmptyData() {
    provider.send(TOKEN, new PushMessage("Title only", null, Map.of()));

    var message = fcm.sends().get(0).body().path("message");
    assertFalse(message.path("notification").has("body"));
    assertFalse(message.has("data"));
  }

  @Test
  void signsTheAccessTokenRequestWithTheServiceAccount() {
    provider.send(TOKEN, MESSAGE);

    var claims = fcm.assertions().get(0);
    assertEquals(FakeFcm.CLIENT_EMAIL, claims.path("iss").asText());
    assertEquals(FcmAccessTokens.SCOPE, claims.path("scope").asText());
    assertEquals(fcm.apiUrl() + "/token", claims.path("aud").asText());
    assertEquals(clock.instant().getEpochSecond(), claims.path("iat").asLong());
    assertEquals(clock.instant().getEpochSecond() + 3600, claims.path("exp").asLong());
  }

  @Test
  void reusesTheAccessTokenUntilShortlyBeforeItExpires() {
    provider.send(TOKEN, MESSAGE);
    clock.advance(Duration.ofMinutes(54));
    provider.send(TOKEN, MESSAGE);
    assertEquals(1, fcm.assertions().size());

    // The token lasts 3599 s; it is renewed 5 minutes early.
    clock.advance(Duration.ofMinutes(1));
    provider.send(TOKEN, MESSAGE);

    assertEquals(2, fcm.assertions().size());
    var sends = fcm.sends();
    assertEquals(sends.get(0).authorization(), sends.get(1).authorization());
    assertNotEquals(sends.get(1).authorization(), sends.get(2).authorization());
  }

  @Test
  void anUnregisteredTokenIsAnInvalidTarget() {
    fcm.answerSends(404, FakeFcm.error(404, "NOT_FOUND", "UNREGISTERED"));

    assertEquals(
        new PushOutcome(PushOutcome.Status.INVALID_TARGET, "HTTP 404 UNREGISTERED"),
        provider.send(TOKEN, MESSAGE));
  }

  @ParameterizedTest
  @CsvSource({
    // Not the target's fault: a bad payload or the wrong Firebase project.
    "400, INVALID_ARGUMENT, INVALID_ARGUMENT, PERMANENT_FAILURE",
    "403, PERMISSION_DENIED, SENDER_ID_MISMATCH, PERMANENT_FAILURE",
    "404, NOT_FOUND, '', PERMANENT_FAILURE",
    "429, RESOURCE_EXHAUSTED, QUOTA_EXCEEDED, TRANSIENT_FAILURE",
    "500, INTERNAL, INTERNAL, TRANSIENT_FAILURE",
    "503, UNAVAILABLE, UNAVAILABLE, TRANSIENT_FAILURE",
    "401, UNAUTHENTICATED, THIRD_PARTY_AUTH_ERROR, TRANSIENT_FAILURE",
  })
  void classifiesFcmErrors(
      int status, String grpcStatus, String errorCode, PushOutcome.Status expected) {
    fcm.answerSends(status, FakeFcm.error(status, grpcStatus, errorCode));

    var outcome = provider.send(TOKEN, MESSAGE);

    assertEquals(expected, outcome.status());
    assertEquals(
        "HTTP " + status + " " + (errorCode.isEmpty() ? grpcStatus : errorCode), outcome.detail());
  }

  @Test
  void anUnparseableErrorIsClassifiedByStatusAlone() {
    fcm.answerSends(502, "<html>Bad gateway</html>");

    assertEquals(
        new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "HTTP 502"),
        provider.send(TOKEN, MESSAGE));
  }

  @Test
  void errorTextIsNeverEchoed() {
    fcm.answerSends(
        400,
        """
        {"error": {"code": 400, "status": "token %s is bad",
          "message": "The registration token %s is not valid"}}
        """
            .formatted(TOKEN, TOKEN));

    var outcome = provider.send(TOKEN, MESSAGE);

    assertEquals(new PushOutcome(PushOutcome.Status.PERMANENT_FAILURE, "HTTP 400"), outcome);
  }

  @Test
  void aRejectedAccessTokenIsReplacedOnTheNextSend() {
    fcm.answerSends(401, FakeFcm.error(401, "UNAUTHENTICATED", "THIRD_PARTY_AUTH_ERROR"));
    provider.send(TOKEN, MESSAGE);
    fcm.answerSends(200, "{}");

    assertEquals(PushOutcome.delivered(), provider.send(TOKEN, MESSAGE));

    assertEquals(2, fcm.assertions().size());
    var sends = fcm.sends();
    assertNotEquals(sends.get(0).authorization(), sends.get(1).authorization());
  }

  @Test
  void aRejectedServiceAccountIsAPermanentFailure() {
    fcm.answerTokens(400, "{\"error\": \"invalid_grant\"}");

    assertEquals(
        new PushOutcome(
            PushOutcome.Status.PERMANENT_FAILURE, "access token request failed: HTTP 400"),
        provider.send(TOKEN, MESSAGE));
    assertTrue(fcm.sends().isEmpty());
  }

  @Test
  void anUnavailableTokenEndpointIsATransientFailure() {
    fcm.answerTokens(503, "");

    assertEquals(PushOutcome.Status.TRANSIENT_FAILURE, provider.send(TOKEN, MESSAGE).status());
    assertTrue(fcm.sends().isEmpty());
  }

  @Test
  void aTokenResponseWithoutATokenIsATransientFailure() {
    fcm.answerTokens(200, "{\"token_type\": \"Bearer\"}");

    assertEquals(PushOutcome.Status.TRANSIENT_FAILURE, provider.send(TOKEN, MESSAGE).status());
  }

  @Test
  void anUnreachableFcmIsATransientFailure() {
    URI stopped;
    try (var closed = new FakeFcm()) {
      stopped = closed.apiUrl();
    }
    var unreachable =
        new FcmPushProvider(fcm.credentials(), stopped, HttpClient.newHttpClient(), clock);
    // The access token comes from the running fake; the send goes to the stopped one.
    var outcome = unreachable.send(TOKEN, MESSAGE);

    assertEquals(PushOutcome.Status.TRANSIENT_FAILURE, outcome.status());
    assertFalse(outcome.detail().contains(TOKEN));
  }

  /** A clock tests move forward by hand. */
  private static final class MutableClock extends Clock {
    private Instant now;

    MutableClock(Instant now) {
      this.now = now;
    }

    void advance(Duration duration) {
      now = now.plus(duration);
    }

    @Override
    public Instant instant() {
      return now;
    }

    @Override
    public ZoneId getZone() {
      return ZoneOffset.UTC;
    }

    @Override
    public Clock withZone(ZoneId zone) {
      return this;
    }
  }
}
