package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.AdminOnly;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import io.github.rodrigofabreu.signalhub.producer.ProducerService;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;
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
 * Test events for the operator: publish an event as an existing producer, to check that pushes
 * arrive and that the devices' preferences filter it as they would the producer's own. Requires the
 * admin token, which can issue a key for any producer already, so this adds no power.
 */
@Path("/api/v1/admin/producers/{id}/events")
@Tag(name = "Event management")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class OperatorEventResource {

  private final EventService events;
  private final ProducerService producers;
  private final Counter published;

  OperatorEventResource(EventService events, ProducerService producers, MeterRegistry registry) {
    this.events = events;
    this.producers = producers;
    // The same meter as the producers' own publishing: a test event is stored like any other.
    this.published =
        Counter.builder("signalhub.events.published")
            .description("Events stored and acknowledged")
            .register(registry);
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Send an event as a producer",
      description =
          "Publishes the event as the producer, with the fields a producer sends: it is stored"
              + " and pushed exactly as the producer's own event would be, through every"
              + " client's push preferences, and bound to the producer in the listing. There is"
              + " no Idempotency-Key: each request stores a new event. Meant for testing pushes"
              + " and preferences; the event is deleted like any other.")
  @APIResponse(
      responseCode = "201",
      description = "Event stored. The Location header points to it.",
      content = @Content(schema = @Schema(implementation = EventResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation, as for a producer.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "The producer is disabled, so it could not publish this event itself.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(
      @Parameter(description = "Canonical producer ID (UUID).") @PathParam("id") UUID id,
      @NotNull @Valid CreateEventRequest request) {
    var producer =
        producers
            .find(id)
            .orElseThrow(() -> error(Response.Status.NOT_FOUND, "Producer not found"));
    if (!producers.isEnabled(id)) {
      throw error(Response.Status.CONFLICT, "Producer is disabled");
    }
    var event = events.createAsOperator(producer, request);
    // Counted once committed: createAsOperator returns only after the transaction.
    published.increment();
    var location = UriBuilder.fromResource(EventResource.class).path(event.id().toString()).build();
    return Response.created(location).entity(event).build();
  }

  private static ClientErrorException error(Response.Status status, String title) {
    return new ClientErrorException(
        Response.status(status)
            .entity(new ApiError(title, status.getStatusCode(), List.of()))
            .build());
  }
}
