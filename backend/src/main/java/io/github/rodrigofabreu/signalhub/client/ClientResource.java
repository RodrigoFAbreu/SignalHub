package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotAuthorizedException;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeType;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.security.SecurityScheme;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * The authenticated client's own registration: read it and manage its push target and push
 * preferences.
 */
@Path("/api/v1/client")
@Tag(
    name = "Client",
    description = "A client installation's own registration. Requires the client's key.")
@SecurityScheme(
    securitySchemeName = ClientResource.SECURITY_SCHEME,
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "shck1_<client id>_<secret>",
    description = "A client key, issued when the operator registers the client.")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class ClientResource {

  public static final String SECURITY_SCHEME = "clientKey";

  private final ClientService clients;
  private final AuthenticatedClient client;

  ClientResource(ClientService clients, AuthenticatedClient client) {
    this.clients = clients;
    this.client = client;
  }

  @GET
  @Operation(summary = "Get this client's registration")
  @APIResponse(
      responseCode = "200",
      description = "The client.",
      content = @Content(schema = @Schema(implementation = ClientResponse.class)))
  public ClientResponse get() {
    return clients.get(client.get());
  }

  @PUT
  @Path("/push-target")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Set this client's push target",
      description =
          "Replaces the client's push target. Call it whenever the push provider issues a new"
              + " token; repeating it with the same values is harmless. If another client had"
              + " the same target, it loses it, so an installation that registers again as a new"
              + " client is never notified twice.")
  @APIResponse(
      responseCode = "200",
      description = "The client with its new push target.",
      content = @Content(schema = @Schema(implementation = ClientResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public ClientResponse setPushTarget(@NotNull @Valid PushTargetRequest request) {
    return clients
        .setPushTarget(client.get().id(), request.provider(), request.token())
        .orElseThrow(ClientResource::revoked);
  }

  @DELETE
  @Path("/push-target")
  @Operation(
      summary = "Remove this client's push target",
      description =
          "The client stops receiving pushes but can still read events. Removing a missing push"
              + " target changes nothing.")
  @APIResponse(
      responseCode = "200",
      description = "The client, without a push target.",
      content = @Content(schema = @Schema(implementation = ClientResponse.class)))
  public ClientResponse clearPushTarget() {
    return clients.clearPushTarget(client.get().id()).orElseThrow(ClientResource::revoked);
  }

  @PUT
  @Path("/push-preferences")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Set this client's push preferences",
      description =
          "Replaces the preferences that decide which events are pushed to this client; an absent"
              + " or null field takes its default. Events that are not pushed are still stored"
              + " and listed. The preferences apply to events not yet dispatched, and are kept"
              + " when the push target changes.")
  @APIResponse(
      responseCode = "200",
      description = "The client with its new push preferences.",
      content = @Content(schema = @Schema(implementation = ClientResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public ClientResponse setPushPreferences(@NotNull @Valid PushPreferencesRequest request) {
    return clients
        .setPushPreferences(client.get().id(), request.toPreferences())
        .orElseThrow(ClientResource::revoked);
  }

  // Revoked between authentication and the change: answer as if the key had been rejected.
  private static NotAuthorizedException revoked() {
    return new NotAuthorizedException(BearerToken.unauthorized());
  }
}
