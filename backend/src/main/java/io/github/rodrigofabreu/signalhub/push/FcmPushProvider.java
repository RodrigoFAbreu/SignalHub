package io.github.rodrigofabreu.signalhub.push;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.quarkus.arc.lookup.LookupUnlessProperty;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.io.IOException;
import java.net.ProxySelector;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.util.Optional;
import java.util.regex.Pattern;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * Firebase Cloud Messaging (HTTP v1 API), provider name {@code fcm}. Active only when {@code
 * SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE} names a service account key file; an unreadable or invalid
 * file stops startup.
 */
@Singleton
@LookupUnlessProperty(
    name = FcmPushProvider.CREDENTIALS_FILE,
    stringValue = "",
    lookupIfMissing = false)
final class FcmPushProvider implements PushProvider {

  static final String NAME = "fcm";
  static final String CREDENTIALS_FILE = "signalhub.push.fcm.credentials-file";

  private static final Logger LOG = Logger.getLogger(FcmPushProvider.class);
  private static final Duration TIMEOUT = Duration.ofSeconds(10);
  // Error codes are echoed into log details only if they look like codes, never free text.
  private static final Pattern CODE = Pattern.compile("[A-Z][A-Z_]{0,63}");

  private final URI sendUri;
  private final FcmAccessTokens tokens;
  private final HttpClient http;
  private final ObjectMapper json = new ObjectMapper();

  @Inject
  FcmPushProvider(
      @ConfigProperty(name = CREDENTIALS_FILE) Optional<String> credentialsFile,
      @ConfigProperty(
              name = "signalhub.push.fcm.api-url",
              defaultValue = "https://fcm.googleapis.com")
          URI apiUrl) {
    this(
        FcmCredentials.read(Path.of(credentialsFile.orElseThrow())),
        apiUrl,
        HttpClient.newBuilder().connectTimeout(TIMEOUT).proxy(ProxySelector.getDefault()).build(),
        Clock.systemUTC());
  }

  FcmPushProvider(FcmCredentials credentials, URI apiUrl, HttpClient http, Clock clock) {
    this.sendUri = apiUrl.resolve("/v1/projects/" + credentials.projectId() + "/messages:send");
    this.tokens = new FcmAccessTokens(credentials, http, clock);
    this.http = http;
    LOG.infof(
        "FCM push enabled for Firebase project %s as %s",
        credentials.projectId(), credentials.clientEmail());
  }

  @Override
  public String name() {
    return NAME;
  }

  @Override
  public PushOutcome send(String token, PushMessage message) {
    try {
      var request =
          HttpRequest.newBuilder(sendUri)
              .timeout(TIMEOUT)
              .header("Authorization", "Bearer " + tokens.get())
              .header("Content-Type", "application/json; charset=UTF-8")
              .POST(
                  HttpRequest.BodyPublishers.ofByteArray(
                      json.writeValueAsBytes(body(token, message))))
              .build();
      var response = http.send(request, HttpResponse.BodyHandlers.ofString());
      return classify(response.statusCode(), response.body());
    } catch (FcmAccessTokens.Failure e) {
      return e.outcome();
    } catch (IOException e) {
      // Connection refused, reset, timed out: the network, not the message.
      return new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, e.getClass().getSimpleName());
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, "interrupted");
    }
  }

  private ObjectNode body(String token, PushMessage message) {
    var root = json.createObjectNode();
    var fcmMessage = root.putObject("message");
    fcmMessage.put("token", token);
    var notification = fcmMessage.putObject("notification");
    notification.put("title", message.title());
    if (message.body() != null) {
      notification.put("body", message.body());
    }
    if (!message.data().isEmpty()) {
      var data = fcmMessage.putObject("data");
      message.data().forEach(data::put);
    }
    return root;
  }

  /**
   * Maps an FCM response to an outcome. Only {@code UNREGISTERED} condemns the target: FCM also
   * answers {@code INVALID_ARGUMENT} for a malformed payload and {@code SENDER_ID_MISMATCH} when
   * SignalHub is configured with the wrong project, and neither is the target's fault.
   */
  private PushOutcome classify(int status, String responseBody) {
    if (status >= 200 && status < 300) {
      return PushOutcome.delivered();
    }
    var error = error(responseBody);
    var errorCode = code(fcmErrorCode(error));
    var reason = errorCode.isEmpty() ? code(error.path("status").asText()) : errorCode;
    var detail = reason.isEmpty() ? "HTTP " + status : "HTTP " + status + " " + reason;
    if ("UNREGISTERED".equals(errorCode)) {
      return new PushOutcome(PushOutcome.Status.INVALID_TARGET, detail);
    }
    if (status == 401) {
      // The access token may have been revoked early; the next send fetches a new one.
      tokens.invalidate();
      return new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, detail);
    }
    if (status == 429 || status >= 500) {
      return new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, detail);
    }
    return new PushOutcome(PushOutcome.Status.PERMANENT_FAILURE, detail);
  }

  private JsonNode error(String responseBody) {
    try {
      var root = json.readTree(responseBody);
      return root == null ? json.missingNode() : root.path("error");
    } catch (IOException e) {
      return json.missingNode();
    }
  }

  private static String fcmErrorCode(JsonNode error) {
    for (var detail : error.path("details")) {
      if (detail.path("@type").asText().endsWith("google.firebase.fcm.v1.FcmError")) {
        return detail.path("errorCode").asText();
      }
    }
    return "";
  }

  private static String code(String candidate) {
    return CODE.matcher(candidate).matches() ? candidate : "";
  }
}
