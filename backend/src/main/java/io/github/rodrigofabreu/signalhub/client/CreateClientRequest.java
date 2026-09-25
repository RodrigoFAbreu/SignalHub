package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code POST /api/v1/admin/clients}. */
@Schema(name = "CreateClientRequest", description = "A client to register.")
public record CreateClientRequest(
    @Schema(
            description =
                "Human-readable label for the installation, e.g. the device it runs on. Need not"
                    + " be unique. Must not be blank.",
            examples = "Pixel 8")
        @NotBlank
        @Size(max = 100)
        @Pattern(regexp = NO_NUL, message = NO_NUL_MESSAGE)
        String name) {

  static final String NO_NUL = "[^\\x00]*";
  static final String NO_NUL_MESSAGE = "must not contain NUL characters";
}
