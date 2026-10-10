package io.github.rodrigofabreu.signalhub.user;

import jakarta.validation.constraints.NotNull;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code PATCH /api/v1/client/users/{id}}. */
@Schema(name = "SetUserRoleRequest", description = "The new role of a user.")
public record SetUserRoleRequest(
    @Schema(
            required = true,
            description =
                "BASIC or MOD. ADMIN is refused (400): admins are made only by the operator.")
        @NotNull
        Role role) {}
