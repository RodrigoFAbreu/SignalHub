package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.AdminOnly;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
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
 * Client management for the operator: register clients, issuing their keys, and revoke them.
 * Requires the admin token, and does not exist unless one is configured.
 */
@Path("/api/v1/admin/clients")
@Tag(
    name = "Client management",
    description =
        "Register the owner's client installations and revoke them. Requires the admin token"
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

  ClientAdminResource(ClientService clients) {
    this.clients = clients;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Register a client",
      description =
          "Creates the client and its key, which is shown only once. Give the key to the client"
              + " installation; it authenticates as the client from then on.")
  @APIResponse(
      responseCode = "201",
      description = "Client created. The Location header points to it.",
      content = @Content(schema = @Schema(implementation = IssuedClientKey.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateClientRequest request) {
    var issued = clients.create(request.name());
    var location = UriBuilder.fromResource(ClientAdminResource.class).path("{id}");
    return Response.created(location.build(issued.client().id())).entity(issued).build();
  }

  @GET
  @Operation(summary = "List clients", description = "All clients, revoked or not, oldest first.")
  @APIResponse(
      responseCode = "200",
      description = "The clients.",
      content = @Content(schema = @Schema(implementation = ClientResponse[].class)))
  public List<ClientResponse> list() {
    return clients.list();
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Get a client")
  @APIResponse(
      responseCode = "200",
      description = "The client.",
      content = @Content(schema = @Schema(implementation = ClientResponse.class)))
  @APIResponse(responseCode = "404", description = "No client has this ID.")
  public ClientResponse get(@PathParam("id") UUID id) {
    return clients.get(id).orElseThrow(ClientAdminResource::notFound);
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

  private static NotFoundException notFound() {
    return new NotFoundException(
        Response.status(Response.Status.NOT_FOUND)
            .entity(new ApiError("Not found", 404, List.of()))
            .build());
  }
}
