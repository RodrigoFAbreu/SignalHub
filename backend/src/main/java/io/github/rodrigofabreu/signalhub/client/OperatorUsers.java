package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import io.github.rodrigofabreu.signalhub.user.UserRef;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.UUID;

/** Resolves the user a management request registers a client or a pairing for. */
@ApplicationScoped
class OperatorUsers {

  static final String ROLES_ARE_PER_USER = "Roles are set per user, not per device";

  private final UserDirectory users;

  OperatorUsers(UserDirectory users) {
    this.users = users;
  }

  /**
   * The named user, or the oldest admin who is not revoked when none is named. Refused when the
   * user is unknown (404) or revoked (409), when no admin exists to default to (409), and when the
   * request asked for an admin device ({@code adminRequested}) for a user who is not an admin
   * (409): a device is an admin device exactly when its user is an ADMIN.
   */
  UserRef target(UUID requested, boolean adminRequested) {
    var user = requested == null ? users.defaultOwner() : users.find(requested);
    if (user.isEmpty()) {
      throw requested == null
          ? conflict("No admin user to default to; give userId")
          : new NotFoundException(
              Response.status(Response.Status.NOT_FOUND)
                  .entity(new ApiError("User not found", 404, List.of()))
                  .build());
    }
    if (!users.isActive(user.get().id())) {
      throw conflict("User is revoked");
    }
    if (adminRequested && !user.get().admin()) {
      throw conflict(ROLES_ARE_PER_USER);
    }
    return user.get();
  }

  static ClientErrorException conflict(String title) {
    return new ClientErrorException(
        Response.status(Response.Status.CONFLICT)
            .entity(new ApiError(title, 409, List.of()))
            .build());
  }
}
