package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.AdminOnly;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
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
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Event management for the operator: delete test or unwanted events. Requires the admin token, and
 * does not exist unless one is configured. Events are otherwise deleted only by retention.
 */
@Path("/api/v1/admin/events")
@Tag(
    name = "Event management",
    description =
        "Delete events: one, a selection, or every event of a producer or older than a time, with"
            + " a dry run that counts them first. Requires the admin token"
            + " (SIGNALHUB_ADMIN_TOKEN); every path answers 404 when none is configured.")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class EventAdminResource {

  private final EventService events;

  EventAdminResource(EventService events) {
    this.events = events;
  }

  @DELETE
  @Path("/{id}")
  @Operation(
      summary = "Delete an event",
      description =
          "Deletes the event for good, with its push if it has not been sent yet and its pushes"
              + " waiting for a retry. Producers, clients and other events are untouched. There"
              + " is no undo.")
  @APIResponse(responseCode = "204", description = "The event is deleted.")
  @APIResponse(
      responseCode = "404",
      description = "No event has this ID, or it was deleted already.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public void delete(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id) {
    if (!events.delete(id)) {
      throw notFound("Event not found");
    }
  }

  @POST
  @Path("/delete")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Delete events",
      description =
          "Deletes a selection of events (ids), or every event matching a filter: of one"
              + " producer (producerId), created before a time (createdBefore), or both. Each"
              + " event goes with its pending push and retries; producers, clients and other"
              + " events are untouched. All or nothing, in one transaction. With dryRun, nothing"
              + " is deleted and the count says how many events match now. There is no undo.")
  @APIResponse(
      responseCode = "200",
      description = "How many events were deleted, or would be with dryRun.",
      content = @Content(schema = @Schema(implementation = DeletedEvents.class)))
  @APIResponse(
      responseCode = "400",
      description =
          "The body is malformed or fails validation, or gives both a selection and a filter,"
              + " or neither.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has the producerId given.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public DeletedEvents deleteAll(@NotNull @Valid DeleteEventsRequest request) {
    if (request.selection() == request.filter()) {
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(
                  new ApiError(
                      "Invalid request",
                      400,
                      List.of(
                          new ApiError.Violation(
                              "",
                              "must give either ids or a filter (producerId, createdBefore or"
                                  + " both)"))))
              .build());
    }
    return events.delete(request).orElseThrow(() -> notFound("Producer not found"));
  }

  private static NotFoundException notFound(String title) {
    return new NotFoundException(
        Response.status(Response.Status.NOT_FOUND)
            .entity(new ApiError(title, 404, List.of()))
            .build());
  }
}
