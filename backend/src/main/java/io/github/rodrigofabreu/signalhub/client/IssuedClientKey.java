package io.github.rodrigofabreu.signalhub.client;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** A newly registered client and its key: the only response that ever contains the key. */
@Schema(
    name = "IssuedClientKey",
    description =
        "A newly registered client. clientKey is shown only in this response: SignalHub stores"
            + " only its hash and cannot show it again.")
public record IssuedClientKey(
    @Schema(required = true) ClientResponse client,
    @Schema(
            required = true,
            description =
                "The client key. The client sends it as `Authorization: Bearer <clientKey>`.",
            examples =
                "shck1_01997d5e8a3c7b1e9f2a4c6d8e0f1a2b_EXAMPLE-not-a-real-key-EXAMPLE-000000000000")
        String clientKey) {

  // The default record toString would print the key if this were ever logged.
  @Override
  public String toString() {
    return "IssuedClientKey[client=" + client.id() + "]";
  }
}
