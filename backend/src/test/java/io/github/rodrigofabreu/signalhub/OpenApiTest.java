package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.hasItems;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;

import io.quarkus.test.junit.QuarkusTest;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

@QuarkusTest
class OpenApiTest {

  private static final String EVENTS = "paths.'/api/v1/events'";
  private static final String EVENT = "paths.'/api/v1/events/{id}'";
  private static final String READ = "paths.'/api/v1/events/{id}/read'";
  private static final String MARK_READ = "paths.'/api/v1/events/read'";
  private static final String UNREAD_COUNT = "paths.'/api/v1/events/unread-count'";
  private static final String SCHEMAS = "components.schemas";
  private static final String ADMIN = "paths.'/api/v1/admin/producers'";

  @Test
  void describesTheServiceIncludingHealthEndpoints() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body("info.title", equalTo("SignalHub API"))
        .body("paths", hasKey("/q/health/live"))
        .body("paths", hasKey("/q/health/ready"));
  }

  @Test
  void describesTheEventEndpoints() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(
            EVENTS + ".post.requestBody.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/CreateEventRequest"))
        .body(EVENTS + ".post.requestBody.content.'application/json'.examples", hasKey("minimal"))
        .body(EVENTS + ".post.responses", hasKey("201"))
        .body(EVENTS + ".post.responses", hasKey("400"))
        .body(EVENTS + ".post.responses", hasKey("401"))
        .body(EVENTS + ".post.responses", hasKey("413"))
        .body(EVENTS + ".post.responses", hasKey("415"))
        .body(EVENTS + ".post.responses", hasKey("200"))
        .body(EVENTS + ".post.responses", hasKey("422"))
        .body(
            EVENTS + ".post.parameters.find { it.name == 'Idempotency-Key' }.in", equalTo("header"))
        .body(
            EVENTS + ".post.parameters.find { it.name == 'Idempotency-Key' }.required",
            not(equalTo(true)))
        .body(EVENT + ".get.responses", hasKey("200"))
        .body(EVENT + ".get.responses", hasKey("401"))
        .body(EVENT + ".get.responses", hasKey("404"))
        .body(
            EVENT + ".get.security",
            containsInAnyOrder(Map.of("clientKey", List.of()), Map.of("adminToken", List.of())));
  }

  @Test
  void describesTheReadState() {
    var owner = containsInAnyOrder(Map.of("clientKey", List.of()), Map.of("adminToken", List.of()));
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(READ + ".put.security", owner)
        .body(READ + ".put.responses", hasKey("404"))
        .body(
            READ + ".put.responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/Event"))
        .body(READ + ".delete.security", owner)
        .body(MARK_READ + ".post.security", owner)
        .body(
            MARK_READ + ".post.requestBody.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/MarkReadRequest"))
        .body(SCHEMAS + ".MarkReadRequest.required", containsInAnyOrder("through"))
        .body(SCHEMAS + ".MarkReadResult.required", containsInAnyOrder("marked"))
        .body(UNREAD_COUNT + ".get.security", owner)
        .body(SCHEMAS + ".UnreadCount.required", containsInAnyOrder("unread"))
        .body(SCHEMAS + ".Event.properties", hasKey("readAt"))
        .body(SCHEMAS + ".Event.required", not(hasItems("readAt")));
  }

  @Test
  void describesTheEventListing() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(
            EVENTS + ".get.security",
            containsInAnyOrder(Map.of("clientKey", List.of()), Map.of("adminToken", List.of())))
        .body(EVENTS + ".post.security", equalTo(List.of(Map.of("producerApiKey", List.of()))))
        .body(
            EVENTS + ".get.parameters.name",
            containsInAnyOrder(
                "producerId",
                "category",
                "severity",
                "createdFrom",
                "createdBefore",
                "cursor",
                "limit"))
        .body(
            EVENTS + ".get.parameters.find { it.name == 'category' }.schema.type", equalTo("array"))
        .body(EVENTS + ".get.parameters.find { it.name == 'limit' }.schema.maximum", equalTo(100))
        .body(EVENTS + ".get.responses", hasKey("200"))
        .body(EVENTS + ".get.responses", hasKey("400"))
        .body(EVENTS + ".get.responses", hasKey("401"))
        .body(EVENTS + ".get.responses", not(hasKey("404")))
        .body(
            EVENTS + ".get.responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/EventPage"))
        .body(SCHEMAS + ".EventPage.required", containsInAnyOrder("items"))
        .body(
            SCHEMAS + ".EventPage.properties.items.items.$ref",
            equalTo("#/components/schemas/Event"));
  }

  @Test
  void describesTheEventModels() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(
            SCHEMAS + ".CreateEventRequest.required",
            containsInAnyOrder("category", "severity", "title"))
        .body(
            SCHEMAS + ".CreateEventRequest.properties.keySet()",
            containsInAnyOrder(
                "context", "category", "severity", "title", "message", "metadata", "occurredAt"))
        .body(SCHEMAS + ".CreateEventRequest.properties.title.maxLength", equalTo(200))
        .body(
            SCHEMAS + ".Event.required",
            hasItems("id", "producer", "category", "severity", "title", "metadata", "createdAt"))
        .body(
            SCHEMAS + ".Event.properties.producer.$ref",
            equalTo("#/components/schemas/EventProducer"))
        .body(SCHEMAS + ".EventProducer.required", containsInAnyOrder("id", "name"))
        .body(
            SCHEMAS + ".Category.enum",
            containsInAnyOrder("ACTION_REQUIRED", "BLOCKED", "COMPLETED", "INFO"))
        .body(SCHEMAS + ".Severity.enum", containsInAnyOrder("LOW", "NORMAL", "HIGH", "CRITICAL"))
        .body(SCHEMAS + ".JsonObject.type", equalTo("object"))
        .body(
            SCHEMAS + ".CreateEventRequest.properties.metadata.$ref",
            equalTo("#/components/schemas/JsonObject"))
        .body(
            SCHEMAS + ".Event.properties.metadata.$ref", equalTo("#/components/schemas/JsonObject"))
        .body(SCHEMAS + ".Error.required", containsInAnyOrder("title", "status", "violations"))
        // Jackson's Java API must not leak into the contract.
        .body(SCHEMAS, not(hasKey("ObjectNode")))
        .body(SCHEMAS, not(hasKey("JsonNode")));
  }

  @Test
  void describesProducerAuthentication() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body("components.securitySchemes.producerApiKey.type", equalTo("http"))
        .body("components.securitySchemes.producerApiKey.scheme", equalTo("bearer"))
        .body(EVENTS + ".post.security", equalTo(List.of(Map.of("producerApiKey", List.of()))))
        // Producers publish; reading an event takes the owner's credential instead.
        .body(EVENT + ".get.security", not(hasItem(Map.of("producerApiKey", List.of()))));
  }

  @Test
  void describesTheProducerManagementApi() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body("components.securitySchemes.adminToken.type", equalTo("http"))
        .body("components.securitySchemes.adminToken.scheme", equalTo("bearer"))
        .body(ADMIN + ".post.security", equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(ADMIN + ".post.responses", hasKey("201"))
        .body(ADMIN + ".post.responses", hasKey("401"))
        .body(ADMIN + ".post.responses", hasKey("409"))
        .body(
            ADMIN + ".post.responses.'201'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/IssuedApiKey"))
        .body("paths", hasKey("/api/v1/admin/producers/{id}"))
        .body("paths", hasKey("/api/v1/admin/producers/{id}/disable"))
        .body("paths", hasKey("/api/v1/admin/producers/{id}/enable"))
        .body("paths", hasKey("/api/v1/admin/producers/{id}/keys"))
        .body("paths", hasKey("/api/v1/admin/producers/{id}/keys/{keyId}/revoke"))
        .body(SCHEMAS + ".IssuedApiKey.required", containsInAnyOrder("producer", "keyId", "apiKey"))
        .body(SCHEMAS + ".Producer.properties", not(hasKey("apiKey")))
        .body(SCHEMAS + ".ApiKey.properties", not(hasKey("keyHash")));
  }

  @Test
  void describesClientRegistration() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body("components.securitySchemes.clientKey.type", equalTo("http"))
        .body("components.securitySchemes.clientKey.scheme", equalTo("bearer"))
        .body(
            "paths.'/api/v1/admin/clients'.post.security",
            equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(
            "paths.'/api/v1/admin/clients'.post.responses.'201'.content.'application/json'"
                + ".schema.$ref",
            equalTo("#/components/schemas/IssuedClientKey"))
        .body("paths", hasKey("/api/v1/admin/clients/{id}"))
        .body("paths", hasKey("/api/v1/admin/clients/{id}/revoke"))
        .body(
            "paths.'/api/v1/client'.get.security", equalTo(List.of(Map.of("clientKey", List.of()))))
        .body("paths.'/api/v1/client/push-target'", hasKey("put"))
        .body("paths.'/api/v1/client/push-target'", hasKey("delete"))
        .body("paths.'/api/v1/client/push-preferences'", hasKey("put"))
        .body(
            SCHEMAS + ".PushPreferences.required",
            containsInAnyOrder("enabled", "minimumSeverity", "mutedCategories", "mutedProducerIds"))
        .body(SCHEMAS + ".Client.required", hasItem("pushPreferences"))
        .body(SCHEMAS + ".IssuedClientKey.required", containsInAnyOrder("client", "clientKey"))
        .body(SCHEMAS + ".PushTargetRequest.required", containsInAnyOrder("provider", "token"))
        .body(SCHEMAS + ".Client.properties", not(hasKey("clientKey")))
        .body(SCHEMAS + ".PushTarget.properties", not(hasKey("token")));
  }
}
