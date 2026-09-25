package io.github.rodrigofabreu.signalhub.producer;

import static io.github.rodrigofabreu.signalhub.TestProducers.ADMIN;
import static io.restassured.RestAssured.given;

import io.quarkus.test.junit.QuarkusTest;
import io.quarkus.test.junit.QuarkusTestProfile;
import io.quarkus.test.junit.TestProfile;
import io.restassured.http.ContentType;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;

/** Without an admin token the management API does not exist, whatever the request carries. */
@QuarkusTest
@TestProfile(AdminApiDisabledTest.Profile.class)
class AdminApiDisabledTest {

  private static final String SOME_TOKEN = "Bearer test-only-admin-token-0123456789abcdef";

  @Test
  void everyManagementPathIsNotFound() {
    given()
        .header("Authorization", SOME_TOKEN)
        .contentType(ContentType.JSON)
        .body("{\"name\": \"disabled-admin\"}")
        .post(ADMIN)
        .then()
        .statusCode(404);
    given().header("Authorization", SOME_TOKEN).get(ADMIN).then().statusCode(404);
    given().get(ADMIN).then().statusCode(404);
    given()
        .header("Authorization", SOME_TOKEN)
        .post(ADMIN + "/" + UUID.randomUUID() + "/keys")
        .then()
        .statusCode(404);
  }

  @Test
  void publishingStillRequiresAProducerKey() {
    given()
        .contentType(ContentType.JSON)
        .body("{\"category\": \"INFO\", \"severity\": \"LOW\", \"title\": \"x\"}")
        .post("/api/v1/events")
        .then()
        .statusCode(401);
  }

  public static class Profile implements QuarkusTestProfile {
    @Override
    public Map<String, String> getConfigOverrides() {
      // An empty value is the same as an unset one.
      return Map.of("signalhub.admin.token", "");
    }
  }
}
