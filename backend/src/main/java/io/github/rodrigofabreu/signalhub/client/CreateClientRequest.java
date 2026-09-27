package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code POST /api/v1/admin/clients} and {@code POST /api/v1/admin/pairings}. */
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
        String name,
    @Schema(
            description =
                "Whether the client is one of the owner's admin devices. Optional; false when"
                    + " omitted or null.")
        Boolean admin) {

  boolean adminRequested() {
    return Boolean.TRUE.equals(admin);
  }

  static final String NO_NUL = "[^\\x00]*";
  static final String NO_NUL_MESSAGE = "must not contain NUL characters";
}
