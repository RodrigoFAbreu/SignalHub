package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.AdminOnly;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * A user's traffic for the operator, for testing and debugging: the user's recent events and the
 * pushes sent to their devices. Requires the admin token; shown to no one else.
 */
@Path("/api/v1/admin/users/{id}/traffic")
@Tag(
    name = "User traffic",
    description =
        "What a user's producers published, what they receive, and how the pushes to their"
            + " devices went. Requires the admin token (SIGNALHUB_ADMIN_TOKEN); every path"
            + " answers 404 when none is configured.")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class UserTrafficResource {

  static final int RECENT = 20;

  private final EventService events;
  private final EventDeliveries deliveries;
  private final UserDirectory users;

  UserTrafficResource(EventService events, EventDeliveries deliveries, UserDirectory users) {
    this.events = events;
    this.deliveries = deliveries;
    this.users = users;
  }

  @GET
  @Operation(
      summary = "A user's recent events and deliveries",
      description =
          "The newest "
              + RECENT
              + " events of the producers the user owns or is subscribed to, and the newest "
              + RECENT
              + " delivery records of their devices (one per push attempt, across events). The"
              + " events' readAt is the operator's own. A revoked user can be inspected too.")
  @APIResponse(
      responseCode = "200",
      description = "The user's traffic.",
      content = @Content(schema = @Schema(implementation = UserTraffic.class)))
  @APIResponse(
      responseCode = "404",
      description = "No user has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public UserTraffic get(@PathParam("id") UUID id) {
    if (users.find(id).isEmpty()) {
      throw new NotFoundException(
          Response.status(Response.Status.NOT_FOUND)
              .entity(new ApiError("User not found", 404, List.of()))
              .build());
    }
    var query =
        new EventQuery(
            Set.of(),
            Set.of(),
            Set.of(),
            Optional.empty(),
            Optional.empty(),
            Optional.empty(),
            Optional.of(id),
            Optional.empty(),
            Optional.empty(),
            RECENT);
    return new UserTraffic(
        events.list(query, Optional.empty()).items(), deliveries.recentFor(id, RECENT));
  }
}
