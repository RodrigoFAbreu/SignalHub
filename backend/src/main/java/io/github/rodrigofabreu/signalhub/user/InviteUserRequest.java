package io.github.rodrigofabreu.signalhub.user;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code POST /api/v1/client/users}. */
@Schema(name = "InviteUserRequest", description = "A user to invite from an admin's device.")
public record InviteUserRequest(
    @Schema(
            required = true,
            description = "The user's name: 1–100 characters, not blank, unique ignoring case.",
            examples = "Anna")
        @NotBlank
        @Size(max = 100)
        @Pattern(regexp = UpdateUserRequest.NO_NUL, message = UpdateUserRequest.NO_NUL_MESSAGE)
        String name,
    @Schema(
            description =
                "BASIC or MOD. Optional; BASIC when omitted or null. ADMIN is refused (400):"
                    + " admins are made only by the operator.")
        Role role,
    @Schema(
            description =
                "The name the user's first device gets when the pairing code is redeemed."
                    + " Optional; \"First device\" when omitted or null.",
            examples = "Pixel 8")
        @Size(max = 100)
        @Pattern(regexp = UpdateUserRequest.NO_NUL, message = UpdateUserRequest.NO_NUL_MESSAGE)
        String deviceName) {

  Role roleOrDefault() {
    return role == null ? Role.BASIC : role;
  }

  String deviceNameOrDefault() {
    return deviceName == null || deviceName.isBlank() ? "First device" : deviceName;
  }
}
