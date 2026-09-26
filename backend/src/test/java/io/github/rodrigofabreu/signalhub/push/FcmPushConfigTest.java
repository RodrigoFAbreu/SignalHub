package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.rodrigofabreu.signalhub.TestClients;
import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.TestProfile;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** With the app's Firebase options configured, clients get them from the client API. */
@QuarkusTest
@TestProfile(FcmDeliveryTest.Profile.class)
class FcmPushConfigTest {

  /** The shape of client/firebase-options.example.json, with made-up values. */
  static final Map<String, String> OPTIONS = options();

  private static final String PUSH_CONFIG = CLIENT + "/push-config";

  @Test
  void aClientGetsTheProviderAndItsOptions() {
    var client = TestClients.register("push-config");

    asClient(client.clientKey())
        .get(PUSH_CONFIG)
        .then()
        .statusCode(200)
        .body("provider", equalTo("fcm"))
        .body("options", equalTo(OPTIONS));
  }

  @Test
  void theConfigurationNeedsAClientKey() {
    given().get(PUSH_CONFIG).then().statusCode(401).body("status", equalTo(401));
  }

  @Test
  void aRevokedClientGetsNothing() {
    var client = TestClients.register("push-config-revoked");
    asAdmin().post(TestClients.ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);

    asClient(client.clientKey()).get(PUSH_CONFIG).then().statusCode(401);
  }

  static Path writeOptions() {
    try {
      var file = Files.createTempFile("fcm-client-options", ".json");
      file.toFile().deleteOnExit();
      return Files.writeString(file, new ObjectMapper().writeValueAsString(OPTIONS));
    } catch (JsonProcessingException e) {
      throw new IllegalStateException(e);
    } catch (IOException e) {
      throw new UncheckedIOException(e);
    }
  }

  private static Map<String, String> options() {
    var options = new LinkedHashMap<String, String>();
    options.put("FIREBASE_PROJECT_ID", FakeFcm.PROJECT);
    options.put("FIREBASE_MESSAGING_SENDER_ID", "123456789012");
    options.put("FIREBASE_ANDROID_API_KEY", "AIza-test-android-key");
    options.put("FIREBASE_ANDROID_APP_ID", "1:123456789012:android:0123456789abcdef");
    options.put("FIREBASE_IOS_API_KEY", "AIza-test-ios-key");
    options.put("FIREBASE_IOS_APP_ID", "1:123456789012:ios:0123456789abcdef");
    return options;
  }
}
