package io.github.rodrigofabreu.signalhub.push;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

class FcmClientOptionsTest {

  @Test
  void readsTheOptionsTheAppIsBuiltWith() throws Exception {
    // Shaped like client/firebase-options.example.json.
    var file = Files.createTempFile("firebase-options", ".json");
    try {
      Files.writeString(
          file,
          """
          {
            "FIREBASE_PROJECT_ID": "your-project-id",
            "FIREBASE_MESSAGING_SENDER_ID": "123456789012",
            "FIREBASE_ANDROID_APP_ID": "1:123456789012:android:0123456789abcdef"
          }
          """);

      var options = new FcmClientOptions(FcmClientOptions.read(file)).options();

      assertEquals("your-project-id", options.get("FIREBASE_PROJECT_ID"));
      assertEquals(
          List.of("FIREBASE_PROJECT_ID", "FIREBASE_MESSAGING_SENDER_ID", "FIREBASE_ANDROID_APP_ID"),
          List.copyOf(options.keySet()));
    } finally {
      Files.delete(file);
    }
  }

  @Test
  void theProviderIsFcm() {
    assertEquals("fcm", new FcmClientOptions(Map.of("A", "b")).provider());
  }

  @Test
  void aMissingFileIsReported() {
    var e =
        assertThrows(
            IllegalStateException.class,
            () -> FcmClientOptions.read(Path.of("/nonexistent/firebase-options.json")));
    assertTrue(e.getMessage().startsWith("Cannot read the FCM client options file"));
  }

  @Test
  void aServiceAccountKeyIsRefused() {
    // Refused however it is recognised, and never echoed.
    for (var json :
        List.of(
            "{\"type\": \"service_account\", \"project_id\": \"p\"}",
            "{\"private_key\": \"secret-value\"}",
            "{\"KEY\": \"-----BEGIN PRIVATE KEY-----secret-value\"}")) {
      var e = assertThrows(IllegalStateException.class, () -> FcmClientOptions.parse(json));
      assertTrue(e.getMessage().contains("looks like a service account key"), e.getMessage());
      assertFalse(e.getMessage().contains("secret-value"), e.getMessage());
    }
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "not json secret-value",
        "[\"secret-value\"]",
        "{}",
        "{\"FIREBASE_PROJECT_ID\": 12}",
        "{\"FIREBASE_PROJECT_ID\": \" \"}",
        "{\"FIREBASE_PROJECT_ID\": {\"nested\": \"secret-value\"}}",
        "{\"FIREBASE PROJECT\": \"secret-value\"}"
      })
  void invalidOptionsAreRefusedWithoutTheirValues(String json) {
    var e = assertThrows(IllegalStateException.class, () -> FcmClientOptions.parse(json));
    assertTrue(e.getMessage().startsWith("The FCM client options file "), e.getMessage());
    assertFalse(e.getMessage().contains("secret-value"), e.getMessage());
  }

  @Test
  void optionsAreBounded() {
    var tooMany = new StringBuilder("{");
    for (int i = 0; i <= FcmClientOptions.MAX_OPTIONS; i++) {
      tooMany.append(i == 0 ? "" : ",").append("\"K").append(i).append("\": \"v\"");
    }
    tooMany.append('}');
    assertThrows(IllegalStateException.class, () -> FcmClientOptions.parse(tooMany.toString()));

    var tooLong = "{\"K\": \"" + "v".repeat(FcmClientOptions.MAX_VALUE_LENGTH + 1) + "\"}";
    assertThrows(IllegalStateException.class, () -> FcmClientOptions.parse(tooLong));
    var longest = "{\"K\": \"" + "v".repeat(FcmClientOptions.MAX_VALUE_LENGTH) + "\"}";
    assertEquals(
        FcmClientOptions.MAX_VALUE_LENGTH, FcmClientOptions.parse(longest).get("K").length());
  }
}
