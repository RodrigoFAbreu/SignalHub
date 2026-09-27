package io.github.rodrigofabreu.signalhub.client;

import java.time.Instant;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** A new pairing: the only response that ever contains its code. */
@Schema(
    name = "Pairing",
    description =
        "A one-time pairing code for a new client. The device redeems it once, before expiresAt,"
            + " to register itself. code is shown only in this response: SignalHub stores only its"
            + " hash.")
public record IssuedPairing(
    @Schema(
            required = true,
            description =
                "The pairing's ID, to ask whether its code was used (PairingStatus). Not a"
                    + " secret: it redeems nothing.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
        UUID id,
    @Schema(
            required = true,
            description = "The name the client gets when the code is redeemed.",
            examples = "Pixel 8")
        String name,
    @Schema(
            required = true,
            description = "Whether the client is an admin device when the code is redeemed.")
        boolean admin,
    @Schema(
            required = true,
            description =
                "The pairing code. The device redeems it with `POST /api/v1/pairing` and"
                    + " `Authorization: Bearer <code>`.",
            examples = "shpc1_EXAMPLE-not-a-code0000")
        String code,
    @Schema(required = true, description = "When the code stops working, if unredeemed.")
        Instant expiresAt,
    @Schema(
            description =
                "The pairing URI, holding the server's public address (SIGNALHUB_PUBLIC_URL) and"
                    + " the code, to show as a QR code; null when no public address is"
                    + " configured.",
            examples =
                "signalhub://pair?server=https%3A%2F%2Fsignalhub.example.com"
                    + "&code=shpc1_EXAMPLE-not-a-code0000")
        String uri) {

  // The default record toString would print the code if this were ever logged.
  @Override
  public String toString() {
    return "IssuedPairing[id="
        + id
        + ", name="
        + name
        + ", admin="
        + admin
        + ", expiresAt="
        + expiresAt
        + "]";
  }
}
