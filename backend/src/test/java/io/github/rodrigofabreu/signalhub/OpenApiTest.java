package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.containsInAnyOrder;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItems;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.not;

import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

@QuarkusTest
class OpenApiTest {

  private static final String EVENTS = "paths.'/api/v1/events'";
  private static final String EVENT = "paths.'/api/v1/events/{id}'";
  private static final String SCHEMAS = "components.schemas";

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
        .body(EVENTS + ".post.responses", hasKey("413"))
        .body(EVENT + ".get.responses", hasKey("200"))
        .body(EVENT + ".get.responses", hasKey("404"));
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
            containsInAnyOrder("source", "category", "severity", "title"))
        .body(
            SCHEMAS + ".CreateEventRequest.properties.keySet()",
            containsInAnyOrder(
                "source",
                "context",
                "category",
                "severity",
                "title",
                "message",
                "metadata",
                "occurredAt"))
        .body(SCHEMAS + ".CreateEventRequest.properties.title.maxLength", equalTo(200))
        .body(
            SCHEMAS + ".Event.required",
            hasItems("id", "source", "category", "severity", "title", "metadata", "createdAt"))
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
}
