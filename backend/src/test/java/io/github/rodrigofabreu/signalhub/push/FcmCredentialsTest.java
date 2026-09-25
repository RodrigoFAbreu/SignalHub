package io.github.rodrigofabreu.signalhub.push;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.nio.file.Path;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class FcmCredentialsTest {

  private static final ObjectMapper JSON = new ObjectMapper();

  private static FakeFcm fcm;

  @BeforeAll
  static void startFake() {
    fcm = new FakeFcm();
  }

  @AfterAll
  static void stopFake() {
    fcm.close();
  }

  @Test
  void readsAServiceAccountKeyFile() {
    var credentials = FcmCredentials.read(fcm.writeCredentials());

    assertEquals(FakeFcm.PROJECT, credentials.projectId());
    assertEquals(FakeFcm.CLIENT_EMAIL, credentials.clientEmail());
    assertEquals(fcm.apiUrl() + "/token", credentials.tokenUri().toString());
    assertEquals("RSA", credentials.privateKey().getAlgorithm());
  }

  @Test
  void neverPrintsThePrivateKey() {
    var text = fcm.credentials().toString();

    assertTrue(text.contains(FakeFcm.PROJECT), text);
    assertFalse(text.contains("PRIVATE"), text);
    assertFalse(text.contains("privateKey"), text);
  }

  @Test
  void aMissingFileIsReported() {
    var e =
        assertThrows(
            IllegalStateException.class,
            () -> FcmCredentials.read(Path.of("/nonexistent/fcm-credentials.json")));
    assertTrue(e.getMessage().contains("Cannot read the FCM credentials file"), e.getMessage());
  }

  @Test
  void invalidJsonIsReportedWithoutQuotingTheFile() {
    var e =
        assertThrows(
            IllegalStateException.class,
            () -> FcmCredentials.parse("{\"private_key\": \"secret-material\""));
    assertFalse(e.getMessage().contains("secret-material"), e.getMessage());
  }

  @Test
  void onlyServiceAccountKeysAreAccepted() {
    var e =
        assertThrows(
            IllegalStateException.class,
            () -> FcmCredentials.parse(with("type", "authorized_user")));
    assertTrue(e.getMessage().contains("service account"), e.getMessage());
  }

  @ParameterizedTest
  @ValueSource(strings = {"project_id", "client_email", "private_key", "token_uri"})
  void aMissingFieldIsNamed(String field) {
    var json = credentials();
    json.remove(field);

    var e = assertThrows(IllegalStateException.class, () -> FcmCredentials.parse(json.toString()));
    assertEquals("The FCM credentials file has no " + field, e.getMessage());
  }

  @Test
  void anInvalidPrivateKeyIsReportedWithoutQuotingIt() {
    var bad = "-----BEGIN PRIVATE KEY-----\nbm90LWEta2V5\n-----END PRIVATE KEY-----\n";

    var e =
        assertThrows(
            IllegalStateException.class, () -> FcmCredentials.parse(with("private_key", bad)));
    assertTrue(e.getMessage().contains("private_key"), e.getMessage());
    assertFalse(e.getMessage().contains("bm90LWEta2V5"), e.getMessage());
  }

  @ParameterizedTest
  @ValueSource(strings = {"oauth2.googleapis.com/token", "ftp://example.com/token", "::"})
  void theTokenUriMustBeAnHttpUrl(String uri) {
    assertThrows(IllegalStateException.class, () -> FcmCredentials.parse(with("token_uri", uri)));
  }

  private static ObjectNode credentials() {
    try {
      return (ObjectNode) JSON.readTree(fcm.credentialsJson());
    } catch (java.io.IOException e) {
      throw new IllegalStateException(e);
    }
  }

  private static String with(String field, String value) {
    var json = credentials();
    json.put(field, value);
    return json.toString();
  }
}
