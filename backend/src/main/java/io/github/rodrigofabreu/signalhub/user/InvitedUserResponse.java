package io.github.rodrigofabreu.signalhub.user;

import io.github.rodrigofabreu.signalhub.client.IssuedPairing;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** A user invited from a device, and the code that pairs their first device. */
@Schema(
    name = "InvitedUser",
    description =
        "A new user and a one-time pairing code for their first device. The code is shown only in"
            + " this response.")
public record InvitedUserResponse(
    @Schema(required = true) UserRef user,
    @Schema(required = true, description = "The pairing for the user's first device.")
        IssuedPairing pairing) {

  // IssuedPairing hides its code from its toString; this one only repeats that.
  @Override
  public String toString() {
    return "InvitedUserResponse[user=" + user.id() + ", pairing=" + pairing + "]";
  }
}
