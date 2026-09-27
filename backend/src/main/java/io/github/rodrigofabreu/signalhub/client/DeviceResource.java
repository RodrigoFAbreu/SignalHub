package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.enterprise.event.Event;
import jakarta.ws.rs.ClientErrorException;
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
 * Device management from an admin device: list every client, make one an admin, and revoke one that
 * is not an admin. Under {@code /api/v1/client}, so the proxy forwards it; everything else, and
 * anything done to an admin, stays with the operator's admin token.
 */
@Path("/api/v1/client/devices")
@Tag(
    name = "Device management",
    description =
        "The owner's devices, managed from an admin device. Requires the key of a client the"
            + " operator made an admin device; every other client key gets 403.")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@APIResponse(
    responseCode = "403",
    description =
        "The client is not an admin device. Answered before the path's client is looked up, so"
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
      summary = "List every device",
      description =
          "All clients, revoked or not, oldest first, with their latest push results, as the"
              + " management API lists them. Never a key or a push token.")
  @APIResponse(
      responseCode = "200",
      description = "The clients, in items.",
      content = @Content(schema = @Schema(implementation = ClientList.class)))
  public ClientList list() {
    return switch (clients.listFor(caller.get().id())) {
      case ClientService.DeviceList.Listed listed -> new ClientList(listed.clients());
      case ClientService.DeviceList.Refused refused -> throw refusal(refused.refusal());
    };
  }

  @POST
  @Path("/{id}/admin")
  @Operation(
      summary = "Make a device an admin",
      description =
          "The client becomes an admin device. Making an admin an admin changes nothing. Only the"
              + " operator can take admin rights away. The owner's devices get a push naming the"
              + " device that did it. The request has no body.")
  @APIResponse(
      responseCode = "200",
      description = "The client, an admin device.",
      content = @Content(schema = @Schema(implementation = ManagedClientResponse.class)))
  @APIResponse(
      responseCode = "404",
      description = "No client has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "The client is revoked.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public ManagedClientResponse makeAdmin(@PathParam("id") UUID id) {
    return apply(
        clients.makeAdminBy(caller.get().id(), id), ClientChangedByDevice.Change.MADE_ADMIN);
  }

  @POST
  @Path("/{id}/revoke")
  @Operation(
      summary = "Revoke a device that is not an admin",
      description =
          "The client's key stops authenticating immediately and permanently, and its push"
              + " target is removed. Revoking a revoked client changes nothing. An admin device,"
              + " this one included, can be revoked only by the operator. The owner's devices get"
              + " a push naming the device that did it. The request has no body.")
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
      description = "The client is an admin device.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public ManagedClientResponse revoke(@PathParam("id") UUID id) {
    return apply(clients.revokeBy(caller.get().id(), id), ClientChangedByDevice.Change.REVOKED);
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
                  by.id(), by.name(), done.client().id(), done.client().name(), change));
        }
        yield done.client();
      }
      case ClientService.DeviceChange.Refused refused -> throw refusal(refused.refusal());
    };
  }

  private static WebApplicationException refusal(ClientService.Refusal refusal) {
    return switch (refusal) {
      // Revoked between authentication and the change: answer as if the key had been rejected.
      case CALLER_REVOKED -> new NotAuthorizedException(BearerToken.unauthorized());
      case NOT_AN_ADMIN -> error(Response.Status.FORBIDDEN, "Not an admin device");
      case UNKNOWN_CLIENT -> error(Response.Status.NOT_FOUND, "Not found");
      case CLIENT_REVOKED -> error(Response.Status.CONFLICT, "Client is revoked");
      case CLIENT_IS_ADMIN -> error(Response.Status.CONFLICT, "Client is an admin device");
    };
  }

  private static WebApplicationException error(Response.Status status, String title) {
    return new ClientErrorException(
        Response.status(status)
            .entity(new ApiError(title, status.getStatusCode(), List.of()))
            .build());
  }
}
