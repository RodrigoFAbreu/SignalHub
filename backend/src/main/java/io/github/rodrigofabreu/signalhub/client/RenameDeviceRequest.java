package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code PATCH /api/v1/client/devices/{id}}. */
@Schema(name = "RenameDeviceRequest", description = "The new name of a device.")
public record RenameDeviceRequest(
    @Schema(
            required = true,
            description =
                "The new name, as when pairing: 1–100 characters, not blank, need not be unique.",
            examples = "Anna's phone")
        @NotBlank
        @Size(max = 100)
        @Pattern(regexp = CreateClientRequest.NO_NUL, message = CreateClientRequest.NO_NUL_MESSAGE)
        String name) {}
