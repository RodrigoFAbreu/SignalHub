package io.github.rodrigofabreu.signalhub;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.client.ClientAuthenticated;
import io.github.rodrigofabreu.signalhub.client.ClientResource;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Which SignalHub release the server is, for any client key: what /q/info reports, minus the rest.
 */
@Path("/api/v1/client/server")
@Tag(name = "Client")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class ServerResource {

  private final BuildInfo build;

  ServerResource(BuildInfo build) {
    this.build = build;
  }

  @Schema(name = "ServerInfo", description = "The release the server is running.")
  public record ServerInfoResponse(
      @Schema(
              required = true,
              description =
                  "The release version without v, or development for a development build.",
              examples = "1.2.3")
          String version,
      @Schema(
              description =
                  "The full commit hash the build was made from; null when the build recorded none.",
              examples = "0a1b2c3d4e5f60718293a4b5c6d7e8f901234567")
          String commit) {}

  @GET
  @Operation(
      summary = "Get the server's version",
      description =
          "The release and commit of the running server, as /q/info reports them, for a client's"
              + " About screen. Any client key may read it.")
  @APIResponse(
      responseCode = "200",
      description = "The server's version.",
      content = @Content(schema = @Schema(implementation = ServerInfoResponse.class)))
  public ServerInfoResponse get() {
    return new ServerInfoResponse(build.version(), build.revision().orElse(null));
  }
}
