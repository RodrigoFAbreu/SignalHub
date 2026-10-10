package io.github.rodrigofabreu.signalhub.user;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.AdminOnly;
import io.github.rodrigofabreu.signalhub.producer.ProducerAccess;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import io.github.rodrigofabreu.signalhub.producer.ProducerService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.PATCH;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * User management for the operator: invite users, rename them, set their role (making a user an
 * admin included, which only the operator can do), revoke them, and subscribe or unsubscribe them
 * to producers they can see. Requires the admin token, and does not exist unless one is configured.
 */
@Path("/api/v1/admin/users")
@Tag(
    name = "User management",
    description =
        "The people SignalHub serves: their roles, devices, producers and subscriptions. Requires"
            + " the admin token (SIGNALHUB_ADMIN_TOKEN); every path answers 404 when none is"
            + " configured. Making a user an admin, or no longer one, is possible only here.")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class UserAdminResource {

  private final UserService users;
  private final UserDirectory directory;
  private final ProducerAccess access;
  private final ProducerService producers;

  UserAdminResource(
      UserService users,
      UserDirectory directory,
      ProducerAccess access,
      ProducerService producers) {
    this.users = users;
    this.directory = directory;
    this.access = access;
    this.producers = producers;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Invite a user",
      description =
          "Creates the user, with no device yet. Give them a device with a pairing code"
              + " (POST /api/v1/admin/pairings with their userId).")
  @APIResponse(
      responseCode = "201",
      description = "User created. The Location header points to it.",
      content = @Content(schema = @Schema(implementation = UserResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "Another user has this name.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateUserRequest request) {
    var created =
        users
            .create(request.name(), request.roleOrDefault())
            .orElseThrow(() -> conflict("User name already exists"));
    var location = UriBuilder.fromResource(UserAdminResource.class).path("{id}");
    return Response.created(location.build(created.id())).entity(created).build();
  }

  @GET
  @Operation(
      summary = "List users",
      description = "All users, revoked or not, oldest first, with devices and subscriptions.")
  @APIResponse(
      responseCode = "200",
      description = "The users, in items.",
      content = @Content(schema = @Schema(implementation = UserList.class)))
  public UserList list() {
    return new UserList(users.list());
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Get a user")
  @APIResponse(
      responseCode = "200",
      description = "The user.",
      content = @Content(schema = @Schema(implementation = UserResponse.class)))
  @APIResponse(responseCode = "404", description = "No user has this ID.")
  public UserResponse get(@PathParam("id") UUID id) {
    return users.get(id).orElseThrow(UserAdminResource::notFound);
  }

  @PATCH
  @Path("/{id}")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Rename a user or change their role",
      description =
          "Changes the fields given: the user's name, their role, or both. The role is BASIC,"
              + " MOD or ADMIN; a device is an admin device exactly when its user is an ADMIN, so"
              + " this makes or unmakes admin devices. A revoked user cannot be changed.")
  @APIResponse(
      responseCode = "200",
      description = "The user, changed.",
      content = @Content(schema = @Schema(implementation = UserResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed, fails validation or changes nothing.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(responseCode = "404", description = "No user has this ID.")
  @APIResponse(
      responseCode = "409",
      description = "The user is revoked, or another user has the new name.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public UserResponse update(@PathParam("id") UUID id, @NotNull @Valid UpdateUserRequest request) {
    if (request.changesNothing()) {
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(
                  new ApiError(
                      "Invalid request",
                      400,
                      List.of(new ApiError.Violation("", "must give name, role or both"))))
              .build());
    }
    return switch (users
        .update(id, request.name(), request.role())
        .orElseThrow(UserAdminResource::notFound)) {
      case UserService.Update.Updated updated -> updated.user();
      case UserService.Update.Revoked revoked -> throw conflict("User is revoked");
      case UserService.Update.NameTaken taken -> throw conflict("User name already exists");
    };
  }

  @POST
  @Path("/{id}/revoke")
  @Operation(
      summary = "Revoke a user",
      description =
          "Revokes all the user's devices, so their keys stop working, and disables their"
              + " producers, so theirs stop working too. Their events stay and can be deleted with"
              + " the event deletion API. A revoked user cannot be an admin: an admin is made a"
              + " basic user as they are revoked. Revoking a revoked user changes nothing. There"
              + " is no undo.")
  @APIResponse(
      responseCode = "200",
      description = "The user, now revoked.",
      content = @Content(schema = @Schema(implementation = UserResponse.class)))
  @APIResponse(responseCode = "404", description = "No user has this ID.")
  public UserResponse revoke(@PathParam("id") UUID id) {
    return users.revoke(id).orElseThrow(UserAdminResource::notFound);
  }

  @PUT
  @Path("/{id}/subscriptions/{producerId}")
  @Operation(
      summary = "Subscribe a user to a producer",
      description =
          "The user receives the producer's events from now on. They must see the producer: it"
              + " is public, they own it, or they are on its allow-list. Subscribing a"
              + " subscribed user changes nothing.")
  @APIResponse(
      responseCode = "200",
      description = "The user, with their subscriptions.",
      content = @Content(schema = @Schema(implementation = UserResponse.class)))
  @APIResponse(responseCode = "404", description = "No user or no producer has this ID.")
  @APIResponse(
      responseCode = "409",
      description = "The user is revoked, or does not see the producer.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public UserResponse subscribe(
      @PathParam("id") UUID id, @PathParam("producerId") UUID producerId) {
    if (directory.find(id).isEmpty() || producers.find(producerId).isEmpty()) {
      throw notFound();
    }
    if (!directory.isActive(id)) {
      throw conflict("User is revoked");
    }
    if (!access.subscribe(id, producerId)) {
      throw conflict("The user does not see this producer");
    }
    return users.get(id).orElseThrow(UserAdminResource::notFound);
  }

  @DELETE
  @Path("/{id}/subscriptions/{producerId}")
  @Operation(
      summary = "Unsubscribe a user from a producer",
      description =
          "The user stops receiving the producer's events, and no longer finds them in their"
              + " inbox. Unsubscribing a user who is not subscribed changes nothing.")
  @APIResponse(
      responseCode = "200",
      description = "The user, with their subscriptions.",
      content = @Content(schema = @Schema(implementation = UserResponse.class)))
  @APIResponse(responseCode = "404", description = "No user has this ID.")
  public UserResponse unsubscribe(
      @PathParam("id") UUID id, @PathParam("producerId") UUID producerId) {
    if (directory.find(id).isEmpty()) {
      throw notFound();
    }
    access.unsubscribe(id, producerId);
    return users.get(id).orElseThrow(UserAdminResource::notFound);
  }

  private static NotFoundException notFound() {
    return new NotFoundException(
        Response.status(Response.Status.NOT_FOUND)
            .entity(new ApiError("Not found", 404, List.of()))
            .build());
  }

  private static ClientErrorException conflict(String title) {
    return new ClientErrorException(
        Response.status(Response.Status.CONFLICT)
            .entity(new ApiError(title, 409, List.of()))
            .build());
  }
}
