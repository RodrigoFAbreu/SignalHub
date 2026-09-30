package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.AdminOnly;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import io.github.rodrigofabreu.signalhub.push.PushClientConfig;
import io.github.rodrigofabreu.signalhub.push.PushClientOptions;
import io.github.rodrigofabreu.signalhub.push.PushProviders;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.time.Duration;
import java.util.List;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * The service's status for the operator's status panel, summed up so the admin page never parses
 * metrics. Requires the admin token, and does not exist unless one is configured.
 */
@Path("/api/v1/admin/status")
@Tag(
    name = "Status",
    description =
        "Whether push is configured, the push backlog and the retention setting. Requires the"
            + " admin token (SIGNALHUB_ADMIN_TOKEN); answers 404 when none is configured.")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class StatusAdminResource {

  private final PushProviders providers;
  private final PushClientConfig clientConfig;
  private final PushDispatches dispatches;
  private final EventPushDispatcher dispatcher;
  private final EventRetention retention;

  StatusAdminResource(
      PushProviders providers,
      PushClientConfig clientConfig,
      PushDispatches dispatches,
      EventPushDispatcher dispatcher,
      EventRetention retention) {
    this.providers = providers;
    this.clientConfig = clientConfig;
    this.dispatches = dispatches;
    this.dispatcher = dispatcher;
    this.retention = retention;
  }

  @GET
  @Operation(
      summary = "Get the service's status",
      description =
          "The push providers enabled and the push options served to apps, the pushes waiting"
              + " to be dispatched or retried (read from the database now), the retries given"
              + " up since the backend started, and the event retention period.")
  @APIResponse(
      responseCode = "200",
      description = "The status.",
      content = @Content(schema = @Schema(implementation = ServiceStatus.class)))
  public ServiceStatus get() {
    var backlog = dispatches.backlog();
    return new ServiceStatus(
        List.copyOf(providers.names()),
        clientConfig.current().map(PushClientOptions::provider).orElse(null),
        backlog.dispatches(),
        backlog.retries(),
        dispatcher.abandonedRetries(),
        retention.retention().map(Duration::toSeconds).orElse(null));
  }
}
