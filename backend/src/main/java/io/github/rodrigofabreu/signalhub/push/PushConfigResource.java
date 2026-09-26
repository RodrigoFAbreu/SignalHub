package io.github.rodrigofabreu.signalhub.push;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.client.ClientAuthenticated;
import io.github.rodrigofabreu.signalhub.client.ClientResource;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/** The push client options for the authenticated client, next to its registration. */
@Path("/api/v1/client/push-config")
@Tag(name = "Client")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class PushConfigResource {

  private final PushClientConfig config;

  PushConfigResource(PushClientConfig config) {
    this.config = config;
  }

  /** What a client needs to set up its push provider. */
  @Schema(
      name = "PushConfig",
      description =
          "What a client needs to set up push on its device. Only client-safe values, never a"
              + " credential able to send pushes.")
  public record PushConfigResponse(
      @Schema(
              required = true,
              description = "The provider to register a push target with.",
              examples = "fcm")
          String provider,
      @Schema(
              required = true,
              description =
                  "The provider's options for the client, as the operator configured them. Their"
                      + " names and meaning are the provider's; SignalHub does not interpret"
                      + " them.")
          Map<String, String> options) {

    public PushConfigResponse {
      // Keeps the configured order.
      options = Collections.unmodifiableMap(new LinkedHashMap<>(options));
    }
  }

  @GET
  @Operation(
      summary = "Get the push configuration for this client",
      description =
          "The options the client app needs to set up push with the server's provider, so an app"
              + " built without them can still receive pushes. Registering a push target still"
              + " needs the client key.")
  @APIResponse(
      responseCode = "200",
      description = "The push configuration.",
      content = @Content(schema = @Schema(implementation = PushConfigResponse.class)))
  @APIResponse(
      responseCode = "404",
      description =
          "The server serves no push configuration: the app needs its own, built in, to receive"
              + " pushes.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public PushConfigResponse get() {
    return config
        .current()
        .map(served -> new PushConfigResponse(served.provider(), served.options()))
        .orElseThrow(
            () ->
                new NotFoundException(
                    Response.status(Response.Status.NOT_FOUND)
                        .entity(new ApiError("No push configuration", 404, List.of()))
                        .build()));
  }
}
