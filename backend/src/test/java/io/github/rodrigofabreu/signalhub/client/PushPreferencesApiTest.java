package io.github.rodrigofabreu.signalhub.client;

import static io.github.rodrigofabreu.signalhub.TestClients.ADMIN;
import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;

/** A client's push preferences through the client API, against real PostgreSQL. */
@QuarkusTest
class PushPreferencesApiTest {

  private static final String PREFERENCES = CLIENT + "/push-preferences";
  private static final String PRODUCER_A = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b";
  private static final String PRODUCER_B = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2c";

  @Test
  void aNewClientGetsEveryPush() {
    var client = TestClients.register("prefs-default");

    asClient(client.clientKey())
        .get(CLIENT)
        .then()
        .statusCode(200)
        .body("pushPreferences.enabled", equalTo(true))
        .body("pushPreferences.minimumSeverity", equalTo("LOW"))
        .body("pushPreferences.mutedCategories", empty())
        .body("pushPreferences.mutedProducerIds", empty());
  }

  @Test
  void aClientReplacesItsPreferences() {
    var client = TestClients.register("prefs-replace");

    put(
            client,
            """
            {"enabled": false, "minimumSeverity": "HIGH",
             "mutedCategories": ["INFO", "COMPLETED", "INFO"],
             "mutedProducerIds": ["%s", "%s", "%s"]}
            """
                .formatted(PRODUCER_B, PRODUCER_A, PRODUCER_B))
        .statusCode(200)
        .body("id", equalTo(client.id().toString()))
        .body("pushPreferences.enabled", equalTo(false))
        .body("pushPreferences.minimumSeverity", equalTo("HIGH"))
        .body("pushPreferences.mutedCategories", equalTo(List.of("COMPLETED", "INFO")))
        .body("pushPreferences.mutedProducerIds", equalTo(List.of(PRODUCER_A, PRODUCER_B)));

    // Stored: read back by the client and by the operator.
    asClient(client.clientKey())
        .get(CLIENT)
        .then()
        .body("pushPreferences.minimumSeverity", equalTo("HIGH"))
        .body("pushPreferences.mutedProducerIds", equalTo(List.of(PRODUCER_A, PRODUCER_B)));
    asAdmin()
        .get(ADMIN + "/" + client.id())
        .then()
        .body("pushPreferences.mutedCategories", equalTo(List.of("COMPLETED", "INFO")));

    // Replacing, not merging: absent fields take their defaults again.
    put(client, "{\"minimumSeverity\": \"NORMAL\"}")
        .statusCode(200)
        .body("pushPreferences.enabled", equalTo(true))
        .body("pushPreferences.minimumSeverity", equalTo("NORMAL"))
        .body("pushPreferences.mutedCategories", empty())
        .body("pushPreferences.mutedProducerIds", empty());
    put(client, "{\"enabled\": null}")
        .statusCode(200)
        .body("pushPreferences.minimumSeverity", equalTo("LOW"));
  }

  @Test
  void preferencesSurviveAPushTargetChange() {
    var client = TestClients.register("prefs-target");
    put(client, "{\"mutedCategories\": [\"INFO\"]}").statusCode(200);

    asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(Map.of("provider", "fcm", "token", "prefs-" + UUID.randomUUID()))
        .put(CLIENT + "/push-target")
        .then()
        .statusCode(200)
        .body("pushPreferences.mutedCategories", equalTo(List.of("INFO")));
    asClient(client.clientKey())
        .delete(CLIENT + "/push-target")
        .then()
        .statusCode(200)
        .body("pushPreferences.mutedCategories", equalTo(List.of("INFO")));
  }

  @ParameterizedTest
  @ValueSource(
      strings = {
        "",
        "null",
        "[]",
        "{\"enabled\": \"false\"}",
        "{\"enabled\": 0}",
        "{\"minimumSeverity\": \"URGENT\"}",
        "{\"minimumSeverity\": \"high\"}",
        "{\"minimumSeverity\": 2}",
        "{\"mutedCategories\": \"INFO\"}",
        "{\"mutedCategories\": [\"NEWS\"]}",
        "{\"mutedCategories\": [null]}",
        "{\"mutedProducerIds\": [\"not-a-uuid\"]}",
        "{\"mutedProducerIds\": [null]}",
        "{\"quietHours\": true}"
      })
  void invalidPreferencesAreRejected(String body) {
    var client = TestClients.register("prefs-invalid");

    put(client, body).statusCode(400);
    asClient(client.clientKey())
        .get(CLIENT)
        .then()
        .body("pushPreferences.minimumSeverity", equalTo("LOW"));
  }

  @Test
  void atMost100ProducersCanBeMuted() {
    var client = TestClients.register("prefs-limit");
    var ids = IntStream.range(0, 101).mapToObj(i -> UUID.randomUUID().toString()).toList();

    put(client, Map.of("mutedProducerIds", ids))
        .statusCode(400)
        .body("violations.field", hasItem("mutedProducerIds"));
    put(client, Map.of("mutedProducerIds", ids.subList(0, 100))).statusCode(200);
  }

  @Test
  void preferencesRequireAnActiveClientKey() {
    given().contentType(ContentType.JSON).body("{}").put(PREFERENCES).then().statusCode(401);
    asAdmin().contentType(ContentType.JSON).body("{}").put(PREFERENCES).then().statusCode(401);

    var client = TestClients.register("prefs-revoked");
    asAdmin().post(ADMIN + "/" + client.id() + "/revoke").then().statusCode(200);
    put(client, "{}").statusCode(401);
  }

  private static io.restassured.response.ValidatableResponse put(
      TestClients.Registered client, Object body) {
    return asClient(client.clientKey())
        .contentType(ContentType.JSON)
        .body(body)
        .put(PREFERENCES)
        .then();
  }
}
