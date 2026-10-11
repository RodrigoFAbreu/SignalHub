package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.user.UserRef;
import java.time.Instant;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** A pairing whose code still works, as listed to the operator. Never the code. */
@Schema(
    name = "OpenPairing",
    description =
        "A pairing the operator created whose code is unused and has not expired. Never contains"
            + " the code, which was shown only when the pairing was created.")
public record OpenPairing(
    @Schema(
            required = true,
            description = "The pairing, as its Pairing response gave it.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
        UUID id,
    @Schema(
            required = true,
            description = "The name the client gets when the code is redeemed.",
            examples = "Pixel 8")
        String name,
    @Schema(required = true, description = "The user the client belongs to when it is redeemed.")
        UserRef user,
    @Schema(required = true, description = "When the code stops working.") Instant expiresAt) {}
