package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code PATCH /api/v1/admin/clients/{id}}: each field present is changed. */
@Schema(
    name = "UpdateClientRequest",
    description =
        "What to change on a client: its name, whether it is an admin device, or both. A field"
            + " that is omitted or null stays as it is; at least one must be given.")
public record UpdateClientRequest(
    @Schema(
            description =
                "The new name, as when registering: 1–100 characters, not blank, need not be"
                    + " unique.",
            examples = "Anna's phone")
        @Size(max = 100)
        @Pattern(regexp = NOT_BLANK, message = "must not be blank")
        @Pattern(regexp = CreateClientRequest.NO_NUL, message = CreateClientRequest.NO_NUL_MESSAGE)
        String name,
    @Schema(description = "true makes the client an admin device; false takes admin rights away.")
        Boolean admin) {

  // A present name has a character that is not whitespace, as @NotBlank requires of a new client.
  private static final String NOT_BLANK = "(?s).*\\S.*";

  boolean changesNothing() {
    return name == null && admin == null;
  }
}
