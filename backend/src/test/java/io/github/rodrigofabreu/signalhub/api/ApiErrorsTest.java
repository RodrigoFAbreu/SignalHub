package io.github.rodrigofabreu.signalhub.api;

import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.emptyString;
import static org.hamcrest.Matchers.equalTo;

import io.github.rodrigofabreu.signalhub.TestProducers;
import io.quarkus.test.junit.QuarkusTest;
import io.restassured.http.ContentType;
import io.restassured.response.ValidatableResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * Errors Quarkus raises before a resource method runs carry the same JSON body as the errors the
 * resources return, so a client parses every product API error one way.
 */
@QuarkusTest
class ApiErrorsTest {

  private static TestProducers.Registered producer;

  @BeforeEach
  void registerProducer() {
    if (producer == null) {
      producer = TestProducers.register("api-errors-test");
    }
  }

  @Test
  void malformedEventIdIsNotFound() {
    assertError(asAdmin().when().get("/api/v1/events/not-a-uuid").then(), 404, "Not Found");
    assertError(asAdmin().when().put("/api/v1/events/not-a-uuid/read").then(), 404, "Not Found");
  }

  @Test
  void malformedManagementIdIsNotFound() {
    assertError(asAdmin().when().get("/api/v1/admin/producers/xyz").then(), 404, "Not Found");
  }

  @Test
  void unknownPathIsNotFound() {
    assertError(given().when().get("/api/v1/nope").then(), 404, "Not Found");
    assertError(asAdmin().when().get("/api/v2/events").then(), 404, "Not Found");
  }

  @Test
  void unsupportedMethodIsNotAllowed() {
    assertError(asAdmin().when().patch("/api/v1/events").then(), 405, "Method Not Allowed");
  }

  @Test
  void unacceptableResponseTypeIsRefused() {
    assertError(
        asAdmin().accept(ContentType.TEXT).when().get("/api/v1/events").then(),
        406,
        "Not Acceptable");
  }

  @Test
  void nonJsonBodyIsUnsupported() {
    assertError(
        TestProducers.asProducer(producer.apiKey())
            .contentType(ContentType.TEXT)
            .body("hello")
            .when()
            .post("/api/v1/events")
            .then(),
        415,
        "Unsupported Media Type");
  }

  @Test
  void resourceErrorsKeepTheirOwnTitle() {
    assertError(
        asAdmin().when().get("/api/v1/events/00000000-0000-0000-0000-000000000000").then(),
        404,
        "Event not found");
  }

  @Test
  void pathsOutsideTheProductApiAreUnchanged() {
    given().when().get("/q/nope").then().statusCode(404).body(emptyString());
  }

  private static ValidatableResponse assertError(
      ValidatableResponse response, int status, String title) {
    return response
        .statusCode(status)
        .contentType(ContentType.JSON)
        .body("title", equalTo(title))
        .body("status", equalTo(status))
        .body("violations", empty());
  }
}
