package io.github.rodrigofabreu.signalhub.push;

import static io.github.rodrigofabreu.signalhub.TestClients.CLIENT;
import static io.github.rodrigofabreu.signalhub.TestClients.asClient;
import static org.hamcrest.Matchers.empty;
import static org.hamcrest.Matchers.equalTo;

import io.github.rodrigofabreu.signalhub.TestClients;
import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

/** Without push client options configured, the server serves none. */
@QuarkusTest
class PushConfigApiTest {

  @Test
  void noConfigurationIsNotFound() {
    var client = TestClients.register("no-push-config");

    asClient(client.clientKey())
        .get(CLIENT + "/push-config")
        .then()
        .statusCode(404)
        .body("title", equalTo("No push configuration"))
        .body("status", equalTo(404))
        .body("violations", empty());
  }
}
