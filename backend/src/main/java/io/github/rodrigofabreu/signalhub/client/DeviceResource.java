package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.enterprise.event.Event;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotAuthorizedException;
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
 * Device management from a device, as its user's role allows: list devices, revoke one and delete a
 * revoked one. Under {@code /api/v1/client}, so the proxy forwards it; making a user an admin, and
 * anything done to an admin's devices, stays with the operator's admin token.
 */
@Path("/api/v1/client/devices")
@Tag(
    name = "Device management",
    description =
        "Devices, managed from a device as its user's role allows. A basic user reads their own"
            + " devices and changes none (403). A mod also revokes and deletes their own devices,"
            + " but not their last active one. An admin also lists every device and revokes and"
            + " deletes those of users who are not admins. Roles are set per user, only by the"
            + " operator with the admin token.")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@APIResponse(
    responseCode = "403",
    description =
        "The user's role does not allow it. Answered before the path's client is looked up, so"
            + " it says nothing about it.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class DeviceResource {

  private final ClientService clients;
  private final AuthenticatedClient caller;
  private final Event<ClientChangedByDevice> changed;

  DeviceResource(
      ClientService clients, AuthenticatedClient caller, Event<ClientChangedByDevice> changed) {
    this.clients = clients;
    this.caller = caller;
    this.changed = changed;
  }

  @GET
  @Operation(
      summary = "List devices",
      description =
          "For an admin, all clients, revoked or not, oldest first; for everyone else, the"
              + " clients of the caller's own user. With their latest push results, as the"
              + " management API lists them. Never a key or a push token.")
  @APIResponse(
      responseCode = "200",
      description = "The clients, in items.",
      content = @Content(schema = @Schema(implementation = ClientList.class)))
  public ClientList list() {
    return switch (clients.listFor(caller.get().id())) {
      case ClientService.DeviceList.Listed listed -> listed.clients();
      case ClientService.DeviceList.Refused refused -> throw refusal(refused.refusal());
    };
  }

  @POST
  @Path("/{id}/admin")
  @Operation(
      summary = "Make a device an admin (no longer possible)",
      description =
          "Refused with 409 whatever the caller and the device: whether a device is an admin"
              + " device follows its user's role, roles are set per user, and a user is made an"
              + " admin, or no longer one, only by the operator on the admin page with the admin"
              + " token. Kept so that an older app gets this answer instead of a missing route."
              + " The request has no body.")
  @APIResponse(
      responseCode = "409",
      description = "Roles are set per user, not per device.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public ManagedClientResponse makeAdmin(@PathParam("id") UUID id) {
    throw error(Response.Status.CONFLICT, OperatorUsers.ROLES_ARE_PER_USER);
  }

  @POST
  @Path("/{id}/revoke")
  @Operation(
      summary = "Revoke a device",
      description =
          "The client's key stops authenticating immediately and permanently, and its push"
              + " target is removed. Revoking a revoked client changes nothing. A mod revokes"
              + " their own devices, but not their last active one. An admin revokes the devices"
              + " of users who are not admins; an admin's devices, this one included, are revoked"
              + " only by the operator. The user's devices and the admins' devices get a push"
              + " naming the device that did it. The request has no body.")
  @APIResponse(
      responseCode = "200",
      description = "The client, now revoked.",
      content = @Content(schema = @Schema(implementation = ManagedClientResponse.class)))
  @APIResponse(
      responseCode = "404",
      description = "No client has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description =
          "The client is an admin device (its user is an admin), or it is the caller's user's last"
              + " active device and the caller is a mod.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public ManagedClientResponse revoke(@PathParam("id") UUID id) {
    return apply(clients.revokeBy(caller.get().id(), id), ClientChangedByDevice.Change.REVOKED);
  }

  @DELETE
  @Path("/{id}")
  @Operation(
      summary = "Delete a revoked device",
      description =
          "Removes the client for good, with its push results, its pushes waiting for a retry"
              + " and the unused pairing codes it created. Events are never deleted, and their"
              + " read state stays. A mod deletes their own revoked devices, an admin those of"
              + " users who are not admins; an active device, this one included, must be revoked"
              + " first. No push is sent: deleting changes nothing a device can use. There is no"
              + " undo.")
  @APIResponse(responseCode = "204", description = "The client is deleted.")
  @APIResponse(
      responseCode = "404",
      description = "No client has this ID, or it was deleted already.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "The client is not revoked, or is an admin device; nothing changed.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public void delete(@PathParam("id") UUID id) {
    clients
        .deleteBy(caller.get().id(), id)
        .ifPresent(
            refusal -> {
              throw refusal(refusal);
            });
  }

  private ManagedClientResponse apply(
      ClientService.DeviceChange result, ClientChangedByDevice.Change change) {
    return switch (result) {
      case ClientService.DeviceChange.Done done -> {
        if (done.changed()) {
          // Fired after the change's transaction committed, so the notice never names a change
          // that was rolled back.
          var by = caller.get();
          changed.fire(
              new ClientChangedByDevice(
                  by.id(),
                  by.name(),
                  done.client().id(),
                  done.client().name(),
                  done.client().user().id(),
                  change));
        }
        yield done.client();
      }
      case ClientService.DeviceChange.Refused refused -> throw refusal(refused.refusal());
    };
  }

  static WebApplicationException refusal(ClientService.Refusal refusal) {
    return switch (refusal) {
      // Revoked between authentication and the change: answer as if the key had been rejected.
      case CALLER_REVOKED -> new NotAuthorizedException(BearerToken.unauthorized());
      case NOT_ALLOWED -> error(Response.Status.FORBIDDEN, "Not allowed for your role");
      case UNKNOWN_CLIENT, UNKNOWN_PAIRING, UNKNOWN_USER ->
          error(Response.Status.NOT_FOUND, "Not found");
      case CLIENT_IS_ADMIN -> error(Response.Status.CONFLICT, "Client is an admin device");
      case CLIENT_NOT_REVOKED -> error(Response.Status.CONFLICT, "Client is not revoked");
      case LAST_DEVICE ->
          error(Response.Status.CONFLICT, "Cannot revoke the last active device of a user");
      case USER_REVOKED -> error(Response.Status.CONFLICT, "User is revoked");
    };
  }

  private static WebApplicationException error(Response.Status status, String title) {
    return new ClientErrorException(
        Response.status(status)
            .entity(new ApiError(title, status.getStatusCode(), List.of()))
            .build());
  }
}
