package io.github.rodrigofabreu.signalhub.push;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.IOException;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;

/**
 * A Firebase service account, read from the JSON key file the Firebase console issues. Only the
 * fields FCM needs are kept. Error messages name the missing or invalid field, never its value.
 */
record FcmCredentials(String projectId, String clientEmail, PrivateKey privateKey, URI tokenUri) {

  static FcmCredentials read(Path file) {
    String json;
    try {
      json = Files.readString(file, StandardCharsets.UTF_8);
    } catch (IOException e) {
      throw new IllegalStateException(
          "Cannot read the FCM credentials file " + file + ": " + e.getClass().getSimpleName(), e);
    }
    return parse(json);
  }

  static FcmCredentials parse(String json) {
    JsonNode root;
    try {
      root = new ObjectMapper().readTree(json);
    } catch (IOException e) {
      // The parser's message may quote the file, which holds a private key.
      throw new IllegalStateException("The FCM credentials file is not valid JSON");
    }
    if (root == null || !root.isObject()) {
      throw new IllegalStateException("The FCM credentials file is not a JSON object");
    }
    if (!"service_account".equals(root.path("type").asText())) {
      throw new IllegalStateException(
          "The FCM credentials file must be a service account key (\"type\": \"service_account\")");
    }
    return new FcmCredentials(
        field(root, "project_id"),
        field(root, "client_email"),
        privateKey(field(root, "private_key")),
        tokenUri(field(root, "token_uri")));
  }

  private static String field(JsonNode root, String name) {
    var value = root.path(name);
    if (!value.isTextual() || value.asText().isBlank()) {
      throw new IllegalStateException("The FCM credentials file has no " + name);
    }
    return value.asText();
  }

  private static PrivateKey privateKey(String pem) {
    var base64 =
        pem.replace("-----BEGIN PRIVATE KEY-----", "").replace("-----END PRIVATE KEY-----", "");
    try {
      var der = Base64.getMimeDecoder().decode(base64);
      return KeyFactory.getInstance("RSA").generatePrivate(new PKCS8EncodedKeySpec(der));
    } catch (IllegalArgumentException | GeneralSecurityException e) {
      throw new IllegalStateException(
          "The private_key of the FCM credentials file is not a PKCS#8 RSA key");
    }
  }

  private static URI tokenUri(String value) {
    try {
      var uri = URI.create(value);
      if (uri.isAbsolute() && ("https".equals(uri.getScheme()) || "http".equals(uri.getScheme()))) {
        return uri;
      }
    } catch (IllegalArgumentException e) {
      // Reported below.
    }
    throw new IllegalStateException("The token_uri of the FCM credentials file is not an HTTP URL");
  }

  @Override
  public String toString() {
    // Keeps the private key out of any log line or exception message.
    return "FcmCredentials[projectId=" + projectId + ", clientEmail=" + clientEmail + "]";
  }
}
