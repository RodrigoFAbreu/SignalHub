package io.github.rodrigofabreu.signalhub.producer;

import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** A newly issued API key: the only response that ever contains a key. */
@Schema(
    name = "IssuedApiKey",
    description =
        "A newly issued API key. apiKey is shown only in this response: SignalHub stores only its"
            + " hash and cannot show it again.")
public record IssuedApiKey(
    @Schema(required = true, description = "The producer, including the new key's record.")
        ProducerResponse producer,
    @Schema(
            required = true,
            description = "ID of the new key.",
            examples = "3f1c0b8e-5d2a-4c7e-9b61-0a8d4e2f7c13")
        UUID keyId,
    @Schema(
            required = true,
            description =
                "The API key. Send it as `Authorization: Bearer <apiKey>` when publishing events.",
            examples =
                "shpk1_3f1c0b8e5d2a4c7e9b610a8d4e2f7c13_EXAMPLE-not-a-real-key-EXAMPLE-000000000000")
        String apiKey) {

  // The default record toString would print the key if this were ever logged.
  @Override
  public String toString() {
    return "IssuedApiKey[producer=" + producer.id() + ", keyId=" + keyId + "]";
  }
}
