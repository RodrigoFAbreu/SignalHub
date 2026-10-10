package io.github.rodrigofabreu.signalhub.user;

import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code PATCH /api/v1/admin/users/{id}}: each field present is changed. */
@Schema(
    name = "UpdateUserRequest",
    description =
        "What to change on a user: their name, their role, or both. A field that is omitted or"
            + " null stays as it is; at least one must be given.")
public record UpdateUserRequest(
    @Schema(description = "The new name, as when inviting: 1–100 characters, not blank, unique.")
        @Size(max = 100)
        @Pattern(regexp = NOT_BLANK, message = "must not be blank")
        @Pattern(regexp = NO_NUL, message = NO_NUL_MESSAGE)
        String name,
    @Schema(description = "The new role: BASIC, MOD or ADMIN.") Role role) {

  static final String NO_NUL = "[^\\x00]*";
  static final String NO_NUL_MESSAGE = "must not contain NUL characters";

  // A present name has a character that is not whitespace, as @NotBlank requires of a new user.
  private static final String NOT_BLANK = "(?s).*\\S.*";

  boolean changesNothing() {
    return name == null && role == null;
  }
}
