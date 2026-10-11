package io.github.rodrigofabreu.signalhub.client;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** The operator's open pairings, soonest to expire first. */
@Schema(
    name = "OpenPairingList",
    description =
        "The pairings the operator created whose codes are unused and unexpired, soonest to expire"
            + " first.")
public record OpenPairingList(
    @Schema(required = true, description = "The open pairings.") List<OpenPairing> items) {

  public OpenPairingList {
    items = List.copyOf(items);
  }
}
