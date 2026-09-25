package io.github.rodrigofabreu.signalhub;

import static io.restassured.RestAssured.given;

import io.restassured.http.ContentType;
import io.restassured.specification.RequestSpecification;
import java.util.UUID;
import org.eclipse.microprofile.config.ConfigProvider;

/** Registers producers through the management API, as an operator would. */
public final class TestProducers {

  public static final String ADMIN = "/api/v1/admin/producers";

  private TestProducers() {}

  /** A registered producer and the API key it was issued. */
  public record Registered(UUID id, String name, UUID keyId, String apiKey) {}

  /** Registers a producer with a unique name starting with {@code prefix}. */
  public static Registered register(String prefix) {
    var name = prefix + "-" + UUID.randomUUID();
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
        UUID.fromString(created.path("producer.id")),
        name,
        UUID.fromString(created.path("keyId")),
        created.path("apiKey"));
  }

  public static RequestSpecification asAdmin() {
    return given().header("Authorization", "Bearer " + adminToken());
  }

  public static RequestSpecification asProducer(String apiKey) {
    return given().header("Authorization", "Bearer " + apiKey);
  }

  public static String adminToken() {
    return ConfigProvider.getConfig().getValue("signalhub.admin.token", String.class);
  }
}
