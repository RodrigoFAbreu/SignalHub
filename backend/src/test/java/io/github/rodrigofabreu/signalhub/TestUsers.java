package io.github.rodrigofabreu.signalhub;

import static io.github.rodrigofabreu.signalhub.TestProducers.asAdmin;

import io.restassured.http.ContentType;
import java.util.UUID;

/** Invites users through the management API, as an operator would. */
public final class TestUsers {

  public static final String ADMIN = "/api/v1/admin/users";

  private TestUsers() {}

  /** An invited user. */
  public record Created(UUID id, String name, String role) {}

  /** Invites a user with a unique name starting with {@code prefix}. */
  public static Created create(String prefix, String role) {
    var name = prefix + "-" + UUID.randomUUID();
    var id =
        asAdmin()
            .contentType(ContentType.JSON)
            .body("{\"name\": \"" + name + "\", \"role\": \"" + role + "\"}")
            .when()
            .post(ADMIN)
            .then()
            .statusCode(201)
            .extract()
            .path("id")
            .toString();
    return new Created(UUID.fromString(id), name, role);
  }

  /** Subscribes the user to the producer, as the operator may. */
  public static void subscribe(UUID userId, UUID producerId) {
    asAdmin()
        .when()
        .put(ADMIN + "/" + userId + "/subscriptions/" + producerId)
        .then()
        .statusCode(200);
  }
}
