package io.github.rodrigofabreu.signalhub.user;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code POST /api/v1/admin/users}. */
@Schema(name = "CreateUserRequest", description = "A user to invite.")
public record CreateUserRequest(
    @Schema(
            required = true,
            description =
                "The user's name: 1–100 characters, not blank, unique ignoring case. Shown to the"
                    + " operator and, in time, to other users.",
            examples = "Anna")
        @NotBlank
        @Size(max = 100)
        @Pattern(regexp = UpdateUserRequest.NO_NUL, message = UpdateUserRequest.NO_NUL_MESSAGE)
        String name,
    @Schema(
            description =
                "BASIC, MOD or ADMIN. Optional; BASIC when omitted or null. Making a user an"
                    + " admin is allowed here because only the operator, with the admin token,"
                    + " calls this API.")
        Role role) {

  Role roleOrDefault() {
    return role == null ? Role.BASIC : role;
  }
}
