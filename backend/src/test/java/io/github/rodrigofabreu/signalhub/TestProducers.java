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

  /**
   * Registers a producer with a unique name starting with {@code prefix}, private and owned by the
   * instance's owner, who is subscribed to it.
   */
  public static Registered register(String prefix) {
    return register(prefix, null, "PRIVATE");
  }

  /** Registers a public producer: every user may see it and subscribe. */
  public static Registered registerPublic(String prefix) {
    return register(prefix, null, "PUBLIC");
  }

  /** Registers a producer owned by the user, with the visibility (PUBLIC or PRIVATE). */
  public static Registered register(String prefix, UUID ownerId, String visibility) {
    var name = prefix + "-" + UUID.randomUUID();
    var body = new java.util.LinkedHashMap<String, Object>();
    body.put("name", name);
    body.put("visibility", visibility);
    if (ownerId != null) {
      body.put("ownerId", ownerId.toString());
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
