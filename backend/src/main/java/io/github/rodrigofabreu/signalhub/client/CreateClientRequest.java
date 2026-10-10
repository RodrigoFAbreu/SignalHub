package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.util.UUID;
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
                "The user the client belongs to. Optional; the oldest admin who is not revoked"
                    + " when omitted or null. Roles are set per user: the client is an admin"
                    + " device exactly when its user is an ADMIN.",
            examples = "01997d5e-8a3c-7b1e-9f2a-4c6d8e0f1a2b")
        UUID userId,
    @Schema(
            description =
                "Deprecated, kept so that requests that sent it still work. Whether the client is"
                    + " an admin device cannot be chosen: true is refused (409) unless the"
                    + " client's user is an admin; false or null changes nothing.")
        Boolean admin) {

  boolean adminRequested() {
    return Boolean.TRUE.equals(admin);
  }

  static final String NO_NUL = "[^\\x00]*";
  static final String NO_NUL_MESSAGE = "must not contain NUL characters";
}
