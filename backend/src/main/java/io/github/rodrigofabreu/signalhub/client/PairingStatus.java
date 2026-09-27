package io.github.rodrigofabreu.signalhub.client;

import java.time.Instant;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.enums.SchemaType;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Whether a pairing was used, for whoever shows its code: the operator or the admin device that
 * created it. Never the code, and never the new client's key.
 */
@Schema(
    name = "PairingStatus",
    description =
        "Whether a pairing's code was redeemed, and as which client. Never contains the code or a"
            + " key. A pairing is answered until 10 minutes after it expires, used or not; then it"
            + " is deleted and unknown.")
public record PairingStatus(
    @Schema(
            required = true,
            description = "The pairing, as its Pairing response gave it.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
        UUID id,
    @Schema(
            required = true,
            type = SchemaType.STRING,
            enumeration = {"PENDING", "REDEEMED", "EXPIRED"},
            description =
                "PENDING: the code still works. REDEEMED: a device redeemed it; client is that"
                    + " device. EXPIRED: it expired unredeemed.")
        State state,
    @Schema(required = true, description = "When the code stops working, if unredeemed.")
        Instant expiresAt,
    @Schema(description = "When the code was redeemed; null unless REDEEMED.") Instant redeemedAt,
    @Schema(description = "The client the code registered; null unless REDEEMED.")
        PairedClient client) {

  /** What became of a pairing's code. */
  public enum State {
    PENDING,
    REDEEMED,
    EXPIRED
  }

  /** The client a redeemed code registered, as it is named now. */
  @Schema(name = "PairedClient", description = "The client a redeemed pairing code registered.")
  public record PairedClient(
      @Schema(required = true, examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2c") UUID id,
      @Schema(
              required = true,
              description = "Its name now; it may have been renamed since it paired.",
              examples = "Pixel 8")
          String name) {}
}
