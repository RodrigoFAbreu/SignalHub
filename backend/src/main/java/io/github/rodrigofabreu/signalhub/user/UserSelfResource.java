package io.github.rodrigofabreu.signalhub.user;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.client.AuthenticatedClient;
import io.github.rodrigofabreu.signalhub.client.ClientAuthenticated;
import io.github.rodrigofabreu.signalhub.client.ClientResource;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotAuthorizedException;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.PATCH;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Users from a device: every role reads the users' names, to choose whom to allow on a producer; an
 * admin invites users and sets a user's role to BASIC or MOD. Under {@code /api/v1/client}, so the
 * proxy forwards it. Making a user an admin, or no longer one, and revoking a user stay with the
 * operator's admin token.
 */
@Path("/api/v1/client/users")
@Tag(
    name = "Users",
    description =
        "The users on the server, from a device. Every role lists their names; inviting a user and"
            + " setting a role are for admins only (403 for anyone else). Admins are made, and"
            + " users revoked, only by the operator with the admin token.")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class UserSelfResource {

  private final UserService users;
  private final UserDirectory directory;
  private final AuthenticatedClient caller;

  UserSelfResource(UserService users, UserDirectory directory, AuthenticatedClient caller) {
    this.users = users;
    this.directory = directory;
    this.caller = caller;
  }

  @GET
  @Operation(
      summary = "List the users' names",
      description =
          "The users who are not revoked, by name, each with an ID and a name only: to choose"
              + " whom to allow on a producer. Never roles, devices or producers.")
  @APIResponse(
      responseCode = "200",
      description = "The users, in items.",
      content = @Content(schema = @Schema(implementation = NamedUserList.class)))
  public NamedUserList list() {
    return new NamedUserList(directory.active().stream().map(NamedUser::of).toList());
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Invite a user",
      description =
          "For an admin's device: creates the user as BASIC or MOD and a one-time pairing code,"
              + " valid for 10 minutes, for their first device; both or neither. The code is shown"
              + " only in this answer. Its status is asked at /api/v1/client/pairings/{id}. The"
              + " admin's devices and the user's get the usual pairing notice when it is redeemed.")
  @APIResponse(
      responseCode = "201",
      description = "User created, with the pairing code for their first device.",
      content = @Content(schema = @Schema(implementation = InvitedUserResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation, or the role is ADMIN.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "403",
      description = "The caller's user is not an admin.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "Another user has this name.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response invite(@NotNull @Valid InviteUserRequest request) {
    var invited =
        refusing(
            () ->
                users.inviteBy(
                    caller.get().userId(),
                    caller.get().id(),
                    request.name(),
                    request.roleOrDefault(),
                    request.deviceNameOrDefault()));
    return Response.status(Response.Status.CREATED)
        .entity(new InvitedUserResponse(invited.user(), invited.pairing()))
        .build();
  }

  @PATCH
  @Path("/{id}")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Set a user's role",
      description =
          "For an admin's device: sets the role of a user who is not an admin to BASIC or MOD."
              + " Their devices stay as they are; what they may do with them follows the role from"
              + " the next request. Making a user an admin, or no longer one, is the operator's.")
  @APIResponse(
      responseCode = "200",
      description = "The user, with their role.",
      content = @Content(schema = @Schema(implementation = UserRef.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation, or the role is ADMIN.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "403",
      description = "The caller's user is not an admin.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No user has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "The user is revoked or an admin.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public UserRef setRole(@PathParam("id") UUID id, @NotNull @Valid SetUserRoleRequest request) {
    return refusing(() -> users.setRoleBy(caller.get().userId(), id, request.role()));
  }

  private static <T> T refusing(java.util.function.Supplier<T> action) {
    try {
      return action.get();
    } catch (UserService.Refused refused) {
      throw refusal(refused.refusal());
    }
  }

  private static WebApplicationException refusal(UserService.Refusal refusal) {
    return switch (refusal) {
      // Revoked between authentication and the change: answer as if the key had been rejected.
      case CALLER_REVOKED -> new NotAuthorizedException(BearerToken.unauthorized());
      case NOT_ALLOWED -> error(Response.Status.FORBIDDEN, "Not allowed for your role");
      case INVALID_ROLE ->
          new BadRequestException(
              Response.status(Response.Status.BAD_REQUEST)
                  .entity(
                      new ApiError(
                          "Invalid request",
                          400,
                          List.of(new ApiError.Violation("role", "must be BASIC or MOD"))))
                  .build());
      case UNKNOWN_USER ->
          new NotFoundException(
              Response.status(Response.Status.NOT_FOUND)
                  .entity(new ApiError("Not found", 404, List.of()))
                  .build());
      case NAME_TAKEN -> error(Response.Status.CONFLICT, "User name already exists");
      case USER_REVOKED -> error(Response.Status.CONFLICT, "User is revoked");
      case USER_IS_ADMIN -> error(Response.Status.CONFLICT, "User is an admin");
    };
  }

  private static ClientErrorException error(Response.Status status, String title) {
    return new ClientErrorException(
        Response.status(status)
            .entity(new ApiError(title, status.getStatusCode(), List.of()))
            .build());
  }
}
