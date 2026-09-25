package io.github.rodrigofabreu.signalhub;

import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;
import static io.restassured.RestAssured.given;

import io.restassured.http.ContentType;
import io.restassured.specification.RequestSpecification;
import java.util.UUID;

/** Registers clients through the management API, as an operator would. */
public final class TestClients {

  public static final String ADMIN = "/api/v1/admin/clients";
  public static final String CLIENT = "/api/v1/client";

  private TestClients() {}

  /** A registered client and the key it was issued. */
  public record Registered(UUID id, String name, String clientKey) {}

  public static Registered register(String name) {
    var created =
        asAdmin()
            .contentType(ContentType.JSON)
            .body("{\"name\": \"" + name + "\"}")
            .when()
            .post(ADMIN)
            .then()
            .statusCode(201)
            .extract();
    return new Registered(
        UUID.fromString(created.path("client.id")), name, created.path("clientKey"));
  }

  public static RequestSpecification asClient(String clientKey) {
    return given().header("Authorization", "Bearer " + clientKey);
  }
}
