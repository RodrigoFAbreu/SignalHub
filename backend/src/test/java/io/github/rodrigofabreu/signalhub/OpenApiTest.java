package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.contains;
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
                "read",
                "createdFrom",
                "createdBefore",
                "cursor",
                "limit"))
        .body(
            EVENTS + ".get.parameters.find { it.name == 'category' }.schema.type", equalTo("array"))
        .body(EVENTS + ".get.parameters.find { it.name == 'limit' }.schema.maximum", equalTo(100))
        .body(EVENTS + ".get.parameters.find { it.name == 'read' }.schema.type", equalTo("boolean"))
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
                "context",
                "category",
                "severity",
                "title",
                "message",
                "metadata",
                "link",
                "occurredAt"))
        .body(SCHEMAS + ".CreateEventRequest.properties.link.maxLength", equalTo(2000))
        .body(SCHEMAS + ".Event.properties.link.type", hasItems("string", "null"))
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
        .body(
            ADMIN + ".get.responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/ProducerList"))
        .body(SCHEMAS + ".ProducerList.required", containsInAnyOrder("items"))
        .body(
            SCHEMAS + ".ProducerList.properties.items.items.$ref",
            equalTo("#/components/schemas/Producer"))
        .body(SCHEMAS + ".IssuedApiKey.required", containsInAnyOrder("producer", "keyId", "apiKey"))
        .body(SCHEMAS + ".Producer.properties", not(hasKey("apiKey")))
        // Optional, and null when the producer has no stored event.
        .body(SCHEMAS + ".Producer.properties", hasKey("lastEventAt"))
        .body(SCHEMAS + ".Producer.required", not(hasItem("lastEventAt")))
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
        .body(
            "paths.'/api/v1/admin/clients'.get.responses.'200'.content.'application/json'"
                + ".schema.$ref",
            equalTo("#/components/schemas/ClientList"))
        .body(SCHEMAS + ".ClientList.required", containsInAnyOrder("items"))
        .body(
            SCHEMAS + ".ClientList.properties.items.items.$ref",
            equalTo("#/components/schemas/ManagedClient"))
        .body(
            "paths.'/api/v1/admin/clients/{id}'.get.responses.'200'.content.'application/json'"
                + ".schema.$ref",
            equalTo("#/components/schemas/ManagedClient"))
        .body(
            "paths.'/api/v1/client'.get.responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/Client"))
        .body("paths", hasKey("/api/v1/admin/clients/{id}/revoke"))
        .body(
            "paths.'/api/v1/client'.get.security", equalTo(List.of(Map.of("clientKey", List.of()))))
        .body("paths.'/api/v1/client/push-target'", hasKey("put"))
        .body("paths.'/api/v1/client/push-target'", hasKey("delete"))
        .body("paths.'/api/v1/client/push-preferences'", hasKey("put"))
        .body(
            "paths.'/api/v1/client/push-config'.get.security",
            equalTo(List.of(Map.of("clientKey", List.of()))))
        .body(
            "paths.'/api/v1/client/push-config'.get.responses.'200'.content.'application/json'"
                + ".schema.$ref",
            equalTo("#/components/schemas/PushConfig"))
        .body("paths.'/api/v1/client/push-config'.get.responses", hasKey("404"))
        .body(SCHEMAS + ".PushConfig.required", containsInAnyOrder("provider", "options"))
        .body(SCHEMAS + ".PushConfig.properties.options.type", equalTo("object"))
        .body(
            SCHEMAS + ".PushPreferences.required",
            containsInAnyOrder("enabled", "minimumSeverity", "mutedCategories", "mutedProducerIds"))
        .body(SCHEMAS + ".Client.required", hasItem("pushPreferences"))
        .body(SCHEMAS + ".IssuedClientKey.required", containsInAnyOrder("client", "clientKey"))
        .body(SCHEMAS + ".PushTargetRequest.required", containsInAnyOrder("provider", "token"))
        .body(SCHEMAS + ".Client.properties", not(hasKey("clientKey")))
        .body(SCHEMAS + ".PushTarget.properties", not(hasKey("token")));
  }

  @Test
  void describesPushResultsOnlyInTheManagementApi() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(
            SCHEMAS + ".ManagedClient.required",
            containsInAnyOrder("id", "name", "admin", "createdAt", "pushPreferences", "pushStatus"))
        .body(
            SCHEMAS + ".ManagedClient.properties.pushStatus.$ref",
            equalTo("#/components/schemas/PushStatus"))
        .body(SCHEMAS + ".Client.properties", not(hasKey("pushStatus")))
        .body(SCHEMAS + ".PushStatus.required", containsInAnyOrder("pendingRetries"))
        .body(SCHEMAS + ".PushSuccess.required", containsInAnyOrder("at", "eventId"))
        .body(SCHEMAS + ".PushFailure.required", containsInAnyOrder("at", "eventId", "result"))
        .body(
            SCHEMAS + ".PushFailure.properties.result.enum",
            containsInAnyOrder(
                "UNSUPPORTED_PROVIDER", "INVALID_TARGET", "TRANSIENT_FAILURE", "PERMANENT_FAILURE"))
        .body(SCHEMAS + ".PushFailure.properties", not(hasKey("token")));
  }

  @Test
  void describesAdminDevicesAndRenaming() {
    var client = "paths.'/api/v1/admin/clients/{id}'.patch";
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(SCHEMAS + ".Client.required", hasItem("admin"))
        .body(SCHEMAS + ".Client.properties.admin.type", equalTo("boolean"))
        .body(SCHEMAS + ".CreateClientRequest.properties.admin.type", equalTo("boolean"))
        .body(SCHEMAS + ".CreateClientRequest.required", containsInAnyOrder("name"))
        .body(client + ".security", equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(
            client + ".requestBody.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/UpdateClientRequest"))
        .body(
            client + ".responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/ManagedClient"))
        .body(client + ".responses", hasKey("400"))
        .body(client + ".responses", hasKey("401"))
        .body(client + ".responses", hasKey("404"))
        .body(client + ".responses", hasKey("409"))
        .body(SCHEMAS + ".UpdateClientRequest.properties", hasKey("name"))
        .body(SCHEMAS + ".UpdateClientRequest.properties.admin.type", equalTo("boolean"))
        .body(SCHEMAS + ".UpdateClientRequest", not(hasKey("required")))
        // Neither the admin page nor the old Connect page is part of the API.
        .body("paths", not(hasKey("/connect")));
  }

  @Test
  void describesDeviceManagementFromAnAdminDevice() {
    var devices = "paths.'/api/v1/client/devices'.get";
    var makeAdmin = "paths.'/api/v1/client/devices/{id}/admin'.post";
    var revoke = "paths.'/api/v1/client/devices/{id}/revoke'.post";
    var delete = "paths.'/api/v1/client/devices/{id}'.delete";
    var clientKey = List.of(Map.of("clientKey", List.of()));
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(devices + ".security", equalTo(clientKey))
        .body(
            devices + ".responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/ClientList"))
        .body(devices + ".responses", hasKey("401"))
        .body(devices + ".responses", hasKey("403"))
        .body(makeAdmin + ".security", equalTo(clientKey))
        .body(
            makeAdmin + ".responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/ManagedClient"))
        .body(makeAdmin + ".responses.keySet()", hasItems("200", "401", "403", "404", "409"))
        .body(makeAdmin, not(hasKey("requestBody")))
        .body(revoke + ".security", equalTo(clientKey))
        .body(
            revoke + ".responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/ManagedClient"))
        .body(revoke + ".responses.keySet()", hasItems("200", "401", "403", "404", "409"))
        .body(revoke, not(hasKey("requestBody")))
        .body(delete + ".security", equalTo(clientKey))
        .body(delete + ".responses.keySet()", containsInAnyOrder("204", "401", "403", "404", "409"))
        .body(delete + ".responses.'204'", not(hasKey("content")))
        // Renaming and taking admin rights away stay with the admin token.
        .body("paths.'/api/v1/client/devices/{id}'.keySet()", containsInAnyOrder("delete"));
  }

  @Test
  void describesDeletingARevokedClient() {
    var delete = "paths.'/api/v1/admin/clients/{id}'.delete";
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(delete + ".security", equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(delete + ".responses.keySet()", containsInAnyOrder("204", "401", "404", "409"))
        .body(delete + ".responses.'204'", not(hasKey("content")))
        .body(
            delete + ".responses.'409'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/Error"))
        .body(delete, not(hasKey("requestBody")));
  }

  @Test
  void describesDeletingEvents() {
    var one = "paths.'/api/v1/admin/events/{id}'.delete";
    var many = "paths.'/api/v1/admin/events/delete'.post";
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(one + ".security", equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(one + ".tags", equalTo(List.of("Event management")))
        .body(one + ".responses.keySet()", containsInAnyOrder("204", "401", "404"))
        .body(one + ".responses.'204'", not(hasKey("content")))
        .body(many + ".security", equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(many + ".tags", equalTo(List.of("Event management")))
        .body(many + ".responses.keySet()", containsInAnyOrder("200", "400", "401", "404"))
        .body(
            many + ".requestBody.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/DeleteEventsRequest"))
        .body(
            many + ".responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/DeletedEvents"))
        .body(
            SCHEMAS + ".DeleteEventsRequest.properties.keySet()",
            containsInAnyOrder("ids", "producerId", "createdBefore", "dryRun"))
        .body(SCHEMAS + ".DeleteEventsRequest.properties.ids.maxItems", equalTo(100))
        .body(SCHEMAS + ".DeleteEventsRequest.properties.dryRun.type", equalTo("boolean"))
        .body(SCHEMAS + ".DeletedEvents.required", containsInAnyOrder("count", "dryRun"))
        // Deleting is management: the event API itself still cannot delete an event.
        .body("paths.'/api/v1/events/{id}'", not(hasKey("delete")));
  }

  @Test
  void describesPairing() {
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body("components.securitySchemes.pairingCode.scheme", equalTo("bearer"))
        .body(
            "paths.'/api/v1/admin/pairings'.post.security",
            equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(
            "paths.'/api/v1/admin/pairings'.post.requestBody.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/CreateClientRequest"))
        .body(
            "paths.'/api/v1/admin/pairings'.post.responses.'201'.content.'application/json'"
                + ".schema.$ref",
            equalTo("#/components/schemas/Pairing"))
        .body(
            SCHEMAS + ".Pairing.required",
            containsInAnyOrder("id", "name", "admin", "code", "expiresAt"))
        .body(SCHEMAS + ".Pairing.properties", hasKey("uri"))
        .body(
            "paths.'/api/v1/admin/pairings/{id}'.get.security",
            equalTo(List.of(Map.of("adminToken", List.of()))))
        .body(
            "paths.'/api/v1/admin/pairings/{id}'.get.responses.'200'.content.'application/json'"
                + ".schema.$ref",
            equalTo("#/components/schemas/PairingStatus"))
        .body(
            "paths.'/api/v1/admin/pairings/{id}'.get.responses.keySet()",
            hasItems("200", "401", "404"))
        .body(SCHEMAS + ".PairingStatus.required", containsInAnyOrder("id", "state", "expiresAt"))
        .body(
            SCHEMAS + ".PairingStatus.properties.state.enum",
            contains("PENDING", "REDEEMED", "EXPIRED"))
        .body(SCHEMAS + ".PairingStatus.properties", hasKey("redeemedAt"))
        .body(
            SCHEMAS + ".PairingStatus.properties.client.$ref",
            equalTo("#/components/schemas/PairedClient"))
        .body(SCHEMAS + ".PairedClient.required", containsInAnyOrder("id", "name"))
        // Whether a code was used never shows the code or a key.
        .body(SCHEMAS + ".PairingStatus.properties", not(hasKey("code")))
        .body(SCHEMAS + ".PairedClient.properties", not(hasKey("clientKey")))
        .body(
            "paths.'/api/v1/pairing'.post.security",
            equalTo(List.of(Map.of("pairingCode", List.of()))))
        .body(
            "paths.'/api/v1/pairing'.post.responses.'201'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/IssuedClientKey"))
        .body("paths.'/api/v1/pairing'.post.responses", hasKey("401"))
        .body("paths.'/api/v1/pairing'.post", not(hasKey("parameters")))
        .body("paths.'/api/v1/pairing'.post", not(hasKey("requestBody")));
  }

  @Test
  void describesPairingFromAnAdminDevice() {
    var create = "paths.'/api/v1/client/pairings'.post";
    var status = "paths.'/api/v1/client/pairings/{id}'.get";
    given()
        .queryParam("format", "json")
        .when()
        .get("/q/openapi")
        .then()
        .statusCode(200)
        .body(create + ".security", equalTo(List.of(Map.of("clientKey", List.of()))))
        .body(create + ".tags", equalTo(List.of("Device management")))
        .body(
            create + ".requestBody.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/CreateDevicePairingRequest"))
        .body(
            create + ".responses.'201'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/Pairing"))
        .body(create + ".responses.keySet()", hasItems("201", "400", "401", "403"))
        .body(status + ".security", equalTo(List.of(Map.of("clientKey", List.of()))))
        .body(status + ".tags", equalTo(List.of("Device management")))
        .body(
            status + ".responses.'200'.content.'application/json'.schema.$ref",
            equalTo("#/components/schemas/PairingStatus"))
        .body(status + ".responses.keySet()", hasItems("200", "401", "403", "404"))
        .body(SCHEMAS + ".CreateDevicePairingRequest.required", equalTo(List.of("name")))
        // An admin device pairs only devices that are not admins.
        .body(SCHEMAS + ".CreateDevicePairingRequest.properties", not(hasKey("admin")));
  }
}
