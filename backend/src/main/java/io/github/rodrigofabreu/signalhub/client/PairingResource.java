package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.enterprise.event.Event;
import jakarta.ws.rs.HeaderParam;
import jakarta.ws.rs.NotAuthorizedException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.HttpHeaders;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeType;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.security.SecurityScheme;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Redeems a pairing code: the device registers itself as a new client. Authenticated only by the
 * code, and outside {@code /api/v1/admin/}, so the proxy forwards it.
 */
@Path("/api/v1/pairing")
@Tag(name = "Client")
@SecurityScheme(
    securitySchemeName = PairingResource.SECURITY_SCHEME,
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "shpc1_<secret>",
    description = "A one-time pairing code, created by the operator.")
@Produces(MediaType.APPLICATION_JSON)
public class PairingResource {

  public static final String SECURITY_SCHEME = "pairingCode";

  private final PairingService pairings;
  private final Event<ClientPaired> paired;

  PairingResource(PairingService pairings, Event<ClientPaired> paired) {
    this.pairings = pairings;
    this.paired = paired;
  }

  @POST
  @SecurityRequirement(name = SECURITY_SCHEME)
  @Operation(
      summary = "Redeem a pairing code",
      description =
          "Registers the calling device as a new client, named as the pairing says, and issues"
              + " its client key, shown only once. The code works once, before it expires. The"
              + " request has no body. The owner's other devices get a push saying a device was"
              + " paired.")
  @APIResponse(
      responseCode = "201",
      description = "Client created. The Location header points to its own registration.",
      content = @Content(schema = @Schema(implementation = IssuedClientKey.class)))
  @APIResponse(
      responseCode = "401",
      description =
          "Missing, malformed, unknown, used or expired pairing code. The response does not say"
              + " which.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response redeem(
      @Parameter(hidden = true) @HeaderParam(HttpHeaders.AUTHORIZATION) String authorization) {
    var issued =
        BearerToken.from(authorization)
            .flatMap(pairings::redeem)
            .orElseThrow(() -> new NotAuthorizedException(BearerToken.unauthorized()));
    // Fired after redeem's transaction committed, so the client it names exists.
    paired.fire(
        new ClientPaired(issued.client().id(), issued.client().name(), issued.client().admin()));
    return Response.created(UriBuilder.fromResource(ClientResource.class).build())
        .entity(issued)
        .build();
  }
}
