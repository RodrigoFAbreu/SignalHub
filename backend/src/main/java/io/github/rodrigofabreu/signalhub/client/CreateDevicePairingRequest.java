package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Body of {@code POST /api/v1/client/pairings}. It has no {@code admin}: an admin device pairs only
 * devices that are not admins, and an unknown property is rejected.
 */
@Schema(
    name = "CreateDevicePairingRequest",
    description =
        "A device to pair from an admin device. It is never an admin device; make it one"
            + " afterwards if needed.")
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
        String name) {}
