package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.AdminOnly;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
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
 * Client management for the operator: register clients for users, issuing their keys, rename them,
 * revoke them, and delete revoked ones. Requires the admin token, and does not exist unless one is
 * configured.
 */
@Path("/api/v1/admin/clients")
@Tag(
    name = "Client management",
    description =
        "Register users' client installations, rename them, revoke them and delete revoked"
            + " ones. Requires the admin token"
            + " (SIGNALHUB_ADMIN_TOKEN); every path answers 404 when none is configured.")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class ClientAdminResource {

  private final ClientService clients;
  private final OperatorUsers operatorUsers;

  ClientAdminResource(ClientService clients, OperatorUsers operatorUsers) {
    this.clients = clients;
    this.operatorUsers = operatorUsers;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Register a client",
      description =
          "Creates the client, a device of the given user (the oldest admin who is not revoked"
              + " when none is given), and its key, which is shown only once. Give the key to the"
              + " client installation; it authenticates as the client from then on. The client"
              + " is an admin device exactly when its user is an ADMIN.")
  @APIResponse(
      responseCode = "201",
      description = "Client created. The Location header points to it.",
      content = @Content(schema = @Schema(implementation = IssuedClientKey.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No user has the given ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description =
          "The user is revoked, none is given and no admin is available, or an admin device was"
              + " asked for a user who is not an admin.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateClientRequest request) {
    var user = operatorUsers.target(request.userId(), request.adminRequested());
    var issued =
        clients
            .create(user.id(), request.name())
            .orElseThrow(() -> OperatorUsers.conflict("User is revoked"));
    var location = UriBuilder.fromResource(ClientAdminResource.class).path("{id}");
    return Response.created(location.build(issued.client().id())).entity(issued).build();
  }

  @GET
  @Operation(
      summary = "List clients",
      description = "All clients, revoked or not, oldest first, with their latest push results.")
  @APIResponse(
      responseCode = "200",
      description = "The clients, in items.",
      content = @Content(schema = @Schema(implementation = ClientList.class)))
  public ClientList list() {
    return new ClientList(clients.list());
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Get a client", description = "The client and its latest push results.")
  @APIResponse(
      responseCode = "200",
      description = "The client.",
      content = @Content(schema = @Schema(implementation = ManagedClientResponse.class)))
  @APIResponse(responseCode = "404", description = "No client has this ID.")
  public ManagedClientResponse get(@PathParam("id") UUID id) {
    return clients.get(id).orElseThrow(ClientAdminResource::notFound);
  }

  @PATCH
  @Path("/{id}")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Rename a client",
      description =
          "Changes the client's name. Whether it is an admin device follows its user's role and"
              + " cannot be changed here: an admin flag other than the current one is refused."
              + " A revoked client cannot be changed.")
  @APIResponse(
      responseCode = "200",
      description = "The client, changed.",
      content = @Content(schema = @Schema(implementation = ManagedClientResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed, fails validation or changes nothing.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(responseCode = "404", description = "No client has this ID.")
  @APIResponse(
      responseCode = "409",
      description =
          "The client is revoked, or the request asks to change its admin flag, which is set"
              + " per user.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public ManagedClientResponse update(
      @PathParam("id") UUID id, @NotNull @Valid UpdateClientRequest request) {
    if (request.changesNothing()) {
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(
                  new ApiError(
                      "Invalid request",
                      400,
                      List.of(new ApiError.Violation("", "must give a name"))))
              .build());
    }
    return switch (clients
        .update(id, request.name(), request.admin())
        .orElseThrow(ClientAdminResource::notFound)) {
      case ClientService.Update.Updated updated -> updated.client();
      case ClientService.Update.Revoked revoked ->
          throw OperatorUsers.conflict("Client is revoked");
      case ClientService.Update.RolesArePerUser perUser ->
          throw OperatorUsers.conflict(OperatorUsers.ROLES_ARE_PER_USER);
    };
  }

  @POST
  @Path("/{id}/revoke")
  @Operation(
      summary = "Revoke a client",
      description =
          "The client's key stops authenticating immediately and permanently, and its push"
              + " target is removed. Revoking a revoked client changes nothing. To replace a"
              + " client, register a new one.")
  @APIResponse(
      responseCode = "200",
      description = "The client, now revoked.",
      content = @Content(schema = @Schema(implementation = ClientResponse.class)))
  @APIResponse(responseCode = "404", description = "No client has this ID.")
  public ClientResponse revoke(@PathParam("id") UUID id) {
    return clients.revoke(id).orElseThrow(ClientAdminResource::notFound);
  }

  @DELETE
  @Path("/{id}")
  @Operation(
      summary = "Delete a revoked client",
      description =
          "Removes the client for good, with its push results, its pushes waiting for a retry"
              + " and the unused pairing codes it created. Events are never deleted, and their"
              + " read state stays. An active client must be revoked first. There is no undo.")
  @APIResponse(responseCode = "204", description = "The client is deleted.")
  @APIResponse(
      responseCode = "404",
      description = "No client has this ID, or it was deleted already.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "The client is not revoked; nothing changed.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public void delete(@PathParam("id") UUID id) {
    switch (clients.delete(id).orElseThrow(ClientAdminResource::notFound)) {
      case DELETED -> {}
      case NOT_REVOKED ->
          throw new ClientErrorException(
              Response.status(Response.Status.CONFLICT)
                  .entity(new ApiError("Client is not revoked", 409, List.of()))
                  .build());
    }
  }

  private static NotFoundException notFound() {
    return new NotFoundException(
        Response.status(Response.Status.NOT_FOUND)
            .entity(new ApiError("Not found", 404, List.of()))
            .build());
  }
}
