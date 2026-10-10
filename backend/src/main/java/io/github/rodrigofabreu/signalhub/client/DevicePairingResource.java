package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Pairing from a device: the same one-time code the operator creates, so a user can add a device
 * from the app, and whether a code it created was used. Under {@code /api/v1/client}, so the proxy
 * forwards it; for mods and admins only, as the rest of device management.
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
    description =
        "The user's role does not allow it (a basic user pairs no device, a mod only for their"
            + " own user). Answered before the path's pairing is looked up, so it says nothing"
            + " about it.",
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
              + " operator does. The device that redeems it becomes a new client of this name that"
              + " belongs to the given user, or to this device's own user, and is an admin device"
              + " exactly when that user is an ADMIN. A mod pairs only for their own user, an"
              + " admin for any user who is not revoked, a basic user for none. The user's devices"
              + " and the admins' devices get a push naming this device. The code stops working"
              + " if this device is revoked, or its user's role no longer allows the pairing,"
              + " before it is redeemed. The code is shown only once.")
  @APIResponse(
      responseCode = "201",
      description = "Pairing created. It has no resource of its own, so no Location.",
      content = @Content(schema = @Schema(implementation = IssuedPairing.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation, admin included.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateDevicePairingRequest request) {
    return switch (pairings.createBy(caller.get().id(), request.name(), request.userId())) {
      case PairingService.DevicePairing.Created created ->
          Response.status(Response.Status.CREATED).entity(created.pairing()).build();
      case PairingService.DevicePairing.Refused refused ->
          throw DeviceResource.refusal(refused.refusal());
    };
  }

  @GET
  @Path("/{id}")
  @Operation(
      summary = "Get whether a pairing this device created was used",
      description =
          "Whether a pairing this device created was redeemed, and as which client, as the"
              + " operator asks about theirs. A pairing is kept until 10 minutes after it expires,"
              + " used or not. Never the code or a key.")
  @APIResponse(
      responseCode = "200",
      description = "The pairing's status.",
      content = @Content(schema = @Schema(implementation = PairingStatus.class)))
  @APIResponse(
      responseCode = "404",
      description =
          "This device created no pairing with this ID, or it was deleted after it expired."
              + " Another device's pairing, or the operator's, is answered the same.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public PairingStatus status(@PathParam("id") UUID id) {
    return switch (pairings.statusFor(caller.get().id(), id)) {
      case PairingService.PairingLookup.Found found -> found.status();
      case PairingService.PairingLookup.Refused refused ->
          throw DeviceResource.refusal(refused.refusal());
    };
  }
}
