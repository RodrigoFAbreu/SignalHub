package io.github.rodrigofabreu.signalhub;

import static io.github.rodrigofabreu.signalhub.TestProducers.asProducer;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsString;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;

import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import jakarta.inject.Inject;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/** The Prometheus endpoint and the meters SignalHub adds to what Quarkus measures. */
@QuarkusTest
class MetricsTest {

  @Inject MeterRegistry registry;

  @Test
  void prometheusEndpointServesRuntimeDatabaseAndSignalHubMeters() {
    // One API request first, so the HTTP server meter exists; /q/ paths are not measured.
    given().get("/api/v1/events/" + UUID.randomUUID()).then().statusCode(404);

    given()
        .accept("text/plain")
        .when()
        .get("/q/metrics")
        .then()
        .statusCode(200)
        .contentType(containsString("text/plain"))
        .body(containsString("jvm_memory_used_bytes"))
        .body(containsString("http_server_requests_seconds_count"))
        .body(containsString("agroal_active_count"))
        .body(containsString("signalhub_events_published_total"))
        .body(containsString("signalhub_events_deleted_total"))
        .body(containsString("signalhub_push_deliveries_total{result=\"delivered\""))
        .body(containsString("signalhub_push_deliveries_total{result=\"transient_failure\""))
        .body(containsString("signalhub_push_retries_abandoned_total"))
        .body(containsString("signalhub_push_dispatch_pending"))
        .body(containsString("signalhub_push_retries_pending"));
  }

  @Test
  void onlyStoredEventsAreCountedAsPublished() {
    var apiKey = TestProducers.register("metrics").apiKey();
    var before = published();

    publish(apiKey, Map.of("category", "INFO", "severity", "LOW", "title", "Counted"))
        .statusCode(201);
    publish(apiKey, Map.of("category", "INFO", "severity", "LOW")).statusCode(400);
    publish("shpk1_not-a-key", Map.of("category", "INFO", "severity", "LOW", "title", "No"))
        .statusCode(401);

    assertEquals(before + 1, published());
  }

  @Test
  void requestPathsAreTemplatedSoEventIdsStayOutOfMetrics() {
    var apiKey = TestProducers.register("metrics").apiKey();
    String id =
        publish(apiKey, Map.of("category", "INFO", "severity", "LOW", "title", "Templated"))
            .statusCode(201)
            .extract()
            .path("id");
    given().get("/api/v1/events/" + id).then().statusCode(200);

    var metrics = given().get("/q/metrics").then().statusCode(200).extract().asString();

    assertFalse(metrics.contains(id));
    assertFalse(metrics.contains(apiKey));
  }

  private double published() {
    return registry.get("signalhub.events.published").counter().count();
  }

  private static ValidatableResponse publish(String apiKey, Map<String, String> body) {
    return asProducer(apiKey)
        .contentType(ContentType.JSON)
        .body(body)
        .post("/api/v1/events")
        .then();
  }
}
