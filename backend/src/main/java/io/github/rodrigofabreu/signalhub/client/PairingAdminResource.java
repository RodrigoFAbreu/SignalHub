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
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Pairing for the operator: a one-time code a new device redeems to register itself, so the device
 * never needs the admin token or a typed client key, and whether it was used. Requires the admin
 * token, and does not exist unless one is configured.
 */
@Path("/api/v1/admin/pairings")
@Tag(name = "Client management")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class PairingAdminResource {

  private final PairingService pairings;

  PairingAdminResource(PairingService pairings) {
    this.pairings = pairings;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Create a pairing for a new client",
      description =
          "Creates a one-time pairing code, valid for 10 minutes, and its pairing URI. The device"
              + " that redeems it becomes a new client of this name, with its own key, and an admin"
              + " device if admin is true. The code is shown only once.")
  @APIResponse(
      responseCode = "201",
      description = "Pairing created. It has no resource of its own, so no Location.",
      content = @Content(schema = @Schema(implementation = IssuedPairing.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateClientRequest request) {
    var pairing = pairings.create(request.name(), request.adminRequested());
    return Response.status(Response.Status.CREATED).entity(pairing).build();
  }

  @GET
  @Path("/{id}")
  @Operation(
      summary = "Get whether a pairing was used",
      description =
          "Whether a pairing created with the admin token was redeemed, and as which client, so"
              + " whoever shows its code learns when a device connected with it. A pairing is kept"
              + " until 10 minutes after it expires, used or not. Never the code or a key.")
  @APIResponse(
      responseCode = "200",
      description = "The pairing's status.",
      content = @Content(schema = @Schema(implementation = PairingStatus.class)))
  @APIResponse(
      responseCode = "404",
      description =
          "No pairing has this ID, it was deleted after it expired, or an admin device created"
              + " it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public PairingStatus status(@PathParam("id") UUID id) {
    return pairings
        .status(id)
        .orElseThrow(
            () ->
                new NotFoundException(
                    Response.status(Response.Status.NOT_FOUND)
                        .entity(new ApiError("Not found", 404, List.of()))
                        .build()));
  }
}
