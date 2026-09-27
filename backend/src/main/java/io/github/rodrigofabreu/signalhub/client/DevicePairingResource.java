package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Pairing from an admin device: the same one-time code the operator creates, so the owner can add a
 * device from the app. Under {@code /api/v1/client}, so the proxy forwards it; admin-only, as the
 * rest of device management.
 */
@Path("/api/v1/client/pairings")
@Tag(name = "Device management")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@APIResponse(
    responseCode = "403",
    description = "The client is not an admin device.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class DevicePairingResource {

  private final PairingService pairings;
  private final AuthenticatedClient caller;

  DevicePairingResource(PairingService pairings, AuthenticatedClient caller) {
    this.pairings = pairings;
    this.caller = caller;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Create a pairing for a new device",
      description =
          "Creates a one-time pairing code, valid for 10 minutes, and its pairing URI, as the"
              + " operator does. The device that redeems it becomes a new client of this name, never"
              + " an admin device, and the owner's devices get a push naming this device. The code"
              + " stops working if this device is revoked or is no longer an admin before it is"
              + " redeemed. The code is shown only once.")
  @APIResponse(
      responseCode = "201",
      description = "Pairing created. It has no resource of its own, so no Location.",
      content = @Content(schema = @Schema(implementation = IssuedPairing.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation, admin included.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateDevicePairingRequest request) {
    return switch (pairings.createBy(caller.get().id(), request.name())) {
      case PairingService.DevicePairing.Created created ->
          Response.status(Response.Status.CREATED).entity(created.pairing()).build();
      case PairingService.DevicePairing.Refused refused ->
          throw DeviceResource.refusal(refused.refusal());
    };
  }
}
