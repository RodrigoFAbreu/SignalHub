package io.github.rodrigofabreu.signalhub.push;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Signature;
import java.util.Arrays;
import java.util.Base64;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.Collectors;

/**
 * An in-process stand-in for Google's OAuth token endpoint and the FCM HTTP v1 API, so tests need
 * no network and no real Firebase project. The token endpoint verifies the signed assertion with
 * the public half of a key generated per instance.
 */
final class FakeFcm implements AutoCloseable {

  static final String PROJECT = "signalhub-test";
  static final String CLIENT_EMAIL = "signalhub@signalhub-test.iam.gserviceaccount.com";

  /** A scripted HTTP answer. */
  record Answer(int status, String body) {}

  /** One request to the send endpoint. */
  record Send(String path, String authorization, JsonNode body) {}

  private static final ObjectMapper JSON = new ObjectMapper();

  private final KeyPair keys;
  private final HttpServer server;
  private final List<Send> sends = new CopyOnWriteArrayList<>();
  private final List<JsonNode> assertions = new CopyOnWriteArrayList<>();
  private final AtomicInteger issued = new AtomicInteger();
  private volatile Answer tokenAnswer;
  private volatile Answer sendAnswer;

  FakeFcm() {
    try {
      var generator = KeyPairGenerator.getInstance("RSA");
      generator.initialize(2048);
      keys = generator.generateKeyPair();
      server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
    } catch (IOException | GeneralSecurityException e) {
      throw new IllegalStateException(e);
    }
    server.createContext("/token", this::token);
    server.createContext("/v1/", this::send);
    reset();
    server.start();
  }

  /** Answers every token request with a fresh token and every send with success again. */
  void reset() {
    tokenAnswer = null;
    sendAnswer = new Answer(200, "{\"name\": \"projects/" + PROJECT + "/messages/1\"}");
    sends.clear();
    assertions.clear();
  }

  void answerTokens(int status, String body) {
    tokenAnswer = new Answer(status, body);
  }

  void answerSends(int status, String body) {
    sendAnswer = new Answer(status, body);
  }

  /** An FCM v1 error response with the given HTTP status, gRPC status and FCM error code. */
  static String error(int status, String grpcStatus, String errorCode) {
    return """
        {"error": {"code": %d, "message": "Requested entity was not found.", "status": "%s",
          "details": [{"@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                       "errorCode": "%s"}]}}
        """
        .formatted(status, grpcStatus, errorCode);
  }

  URI apiUrl() {
    return URI.create("http://127.0.0.1:" + server.getAddress().getPort());
  }

  List<Send> sends() {
    return List.copyOf(sends);
  }

  /** The verified claims of every assertion the token endpoint accepted. */
  List<JsonNode> assertions() {
    return List.copyOf(assertions);
  }

  /** A service account key file, as the Firebase console issues it, for this fake. */
  String credentialsJson() {
    var pem =
        "-----BEGIN PRIVATE KEY-----\n"
            + Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
                .encodeToString(keys.getPrivate().getEncoded())
            + "\n-----END PRIVATE KEY-----\n";
    try {
      return JSON.writeValueAsString(
          Map.of(
              "type",
              "service_account",
              "project_id",
              PROJECT,
              "private_key_id",
              "0123456789abcdef",
              "private_key",
              pem,
              "client_email",
              CLIENT_EMAIL,
              "token_uri",
              apiUrl() + "/token"));
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
  }

  Path writeCredentials() {
    try {
      var file = Files.createTempFile("fcm-credentials", ".json");
      file.toFile().deleteOnExit();
      return Files.writeString(file, credentialsJson());
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
  }

  FcmCredentials credentials() {
    return FcmCredentials.parse(credentialsJson());
  }

  @Override
  public void close() {
    server.stop(0);
  }

  private void token(HttpExchange exchange) throws IOException {
    var answer = tokenAnswer;
    if (answer != null) {
      respond(exchange, answer);
      return;
    }
    var form = form(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
    if (!"urn:ietf:params:oauth:grant-type:jwt-bearer".equals(form.get("grant_type"))) {
      respond(exchange, new Answer(400, "{\"error\": \"unsupported_grant_type\"}"));
      return;
    }
    var claims = verified(form.getOrDefault("assertion", ""));
    if (claims == null) {
      respond(exchange, new Answer(400, "{\"error\": \"invalid_grant\"}"));
      return;
    }
    assertions.add(claims);
    respond(
        exchange,
        new Answer(
            200,
            "{\"access_token\": \"access-%d\", \"expires_in\": 3599, \"token_type\": \"Bearer\"}"
                .formatted(issued.incrementAndGet())));
  }

  private void send(HttpExchange exchange) throws IOException {
    var body = JSON.readTree(exchange.getRequestBody());
    sends.add(
        new Send(
            exchange.getRequestURI().getPath(),
            exchange.getRequestHeaders().getFirst("Authorization"),
            body));
    respond(exchange, sendAnswer);
  }

  private JsonNode verified(String jwt) {
    var parts = jwt.split("\\.");
    if (parts.length != 3) {
      return null;
    }
    try {
      var signature = Signature.getInstance("SHA256withRSA");
      signature.initVerify(keys.getPublic());
      signature.update((parts[0] + "." + parts[1]).getBytes(StandardCharsets.US_ASCII));
      if (!signature.verify(Base64.getUrlDecoder().decode(parts[2]))) {
        return null;
      }
      var header = JSON.readTree(Base64.getUrlDecoder().decode(parts[0]));
      if (!"RS256".equals(header.path("alg").asText())) {
        return null;
      }
      return JSON.readTree(Base64.getUrlDecoder().decode(parts[1]));
    } catch (GeneralSecurityException | IOException | IllegalArgumentException e) {
      return null;
    }
  }

  private static Map<String, String> form(String body) {
    return Arrays.stream(body.split("&"))
        .map(pair -> pair.split("=", 2))
        .filter(pair -> pair.length == 2)
        .collect(
            Collectors.toMap(
                pair -> URLDecoder.decode(pair[0], StandardCharsets.UTF_8),
                pair -> URLDecoder.decode(pair[1], StandardCharsets.UTF_8),
                (first, second) -> first));
  }

  private static void respond(HttpExchange exchange, Answer answer) throws IOException {
    var bytes = answer.body().getBytes(StandardCharsets.UTF_8);
    exchange.getResponseHeaders().set("Content-Type", "application/json");
    exchange.sendResponseHeaders(answer.status(), bytes.length == 0 ? -1 : bytes.length);
    try (var out = exchange.getResponseBody()) {
      out.write(bytes);
    }
  }
}
