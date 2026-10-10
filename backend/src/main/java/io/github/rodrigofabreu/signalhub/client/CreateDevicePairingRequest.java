package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Body of {@code POST /api/v1/client/pairings}. It has no {@code admin}: roles are set per user,
 * and an unknown property is rejected.
 */
@Schema(
    name = "CreateDevicePairingRequest",
    description =
        "A device to pair from a device of a mod or an admin. It belongs to the given user, or to"
            + " this device's own user, and is an admin device exactly when that user is an"
            + " ADMIN.")
public record CreateDevicePairingRequest(
    @Schema(
            required = true,
            description =
                "Human-readable label for the new installation, e.g. the device it runs on. Need"
                    + " not be unique. Must not be blank.",
            examples = "Pixel 8")
        @NotBlank
        @Size(max = 100)
        @Pattern(regexp = CreateClientRequest.NO_NUL, message = CreateClientRequest.NO_NUL_MESSAGE)
        String name,
    @Schema(
            description =
                "The user the new device belongs to. Optional; this device's own user when"
                    + " omitted or null. Only an admin may name another user.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
        UUID userId) {}
