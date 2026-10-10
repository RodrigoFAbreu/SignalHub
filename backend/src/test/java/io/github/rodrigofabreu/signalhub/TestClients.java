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
  public record Registered(UUID id, String name, String clientKey, UUID userId) {}

  /**
   * Registers a device of the instance's owner, the admin the migration creates: an admin device,
   * subscribed to every producer {@link TestProducers} registers.
   */
  public static Registered register(String name) {
    return registerFor(null, name);
  }

  /** The same as {@link #register}, for tests that want to say the device is an admin one. */
  public static Registered registerAdmin(String name) {
    return register(name);
  }

  /** Registers a device of the user, or of the owner when {@code userId} is null. */
  public static Registered registerFor(UUID userId, String name) {
    var body = new java.util.LinkedHashMap<String, Object>();
    body.put("name", name);
    if (userId != null) {
      body.put("userId", userId.toString());
    }
    var created =
        asAdmin()
            .contentType(ContentType.JSON)
            .body(body)
            .when()
            .post(ADMIN)
            .then()
            .statusCode(201)
            .extract();
    return new Registered(
        UUID.fromString(created.path("client.id")),
        name,
        created.path("clientKey"),
        UUID.fromString(created.path("client.user.id")));
  }

  /** Registers a device of a new user with this role: BASIC, MOD or ADMIN. */
  public static Registered registerAs(String role, String name) {
    return registerFor(TestUsers.create(name + "-user", role).id(), name);
  }

  /**
   * Registers a device of a new user with this role who is subscribed to the producers, so it
   * receives their events whatever their visibility; the producers must be public, or the user's.
   */
  public static Registered registerSubscribed(
      String role, String name, TestProducers.Registered... producers) {
    var device = registerAs(role, name);
    for (var producer : producers) {
      TestUsers.subscribe(device.userId(), producer.id());
    }
    return device;
  }

  public static RequestSpecification asClient(String clientKey) {
    return given().header("Authorization", "Bearer " + clientKey);
  }
}
