package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.client.ClientResource;
import io.github.rodrigofabreu.signalhub.client.OwnerAuthenticated;
import io.github.rodrigofabreu.signalhub.producer.AuthenticatedProducer;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import io.github.rodrigofabreu.signalhub.producer.ProducerAuthenticated;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.QueryParam;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.enums.SchemaType;
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeType;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.ExampleObject;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.parameters.Parameter;
import org.eclipse.microprofile.openapi.annotations.parameters.RequestBody;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.security.SecurityScheme;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

@Path("/api/v1/events")
@Tag(name = "Events", description = "Publish, list and read generic events.")
@SecurityScheme(
    securitySchemeName = EventResource.SECURITY_SCHEME,
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    bearerFormat = "shpk1_<key id>_<secret>",
    description =
        "A producer API key, issued through the producer management API. The event is bound to"
            + " the producer that owns the key.")
@Consumes(MediaType.APPLICATION_JSON)
@Produces(MediaType.APPLICATION_JSON)
public class EventResource {

  static final String SECURITY_SCHEME = "producerApiKey";

  private final EventService events;
  private final AuthenticatedProducer producer;

  EventResource(EventService events, AuthenticatedProducer producer) {
    this.events = events;
    this.producer = producer;
  }

  @POST
  @ProducerAuthenticated
  @SecurityRequirement(name = SECURITY_SCHEME)
  @Operation(
      summary = "Publish an event",
      description =
          "Authenticates the producer, validates the event and stores it durably before"
              + " responding. The event is bound to the authenticated producer. The response is"
              + " the canonical event, including the server-generated id, producer and"
              + " createdAt.")
  @RequestBody(
      required = true,
      content =
          @Content(
              mediaType = MediaType.APPLICATION_JSON,
              schema = @Schema(implementation = CreateEventRequest.class),
              examples = {
                @ExampleObject(name = "ci", summary = "A CI system", value = CI_EXAMPLE),
                @ExampleObject(
                    name = "agent",
                    summary = "An autonomous agent waiting for approval",
                    value = AGENT_EXAMPLE),
                @ExampleObject(name = "minimal", summary = "Required fields only", value = MINIMAL)
              }))
  @APIResponse(
      responseCode = "201",
      description = "Event stored. The Location header points to it.",
      content = @Content(schema = @Schema(implementation = EventResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "401",
      description =
          "Missing, malformed, unknown or revoked API key, or the producer is disabled. The"
              + " response does not say which.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(responseCode = "413", description = "The body is larger than 64 KiB.")
  public Response create(@NotNull @Valid CreateEventRequest request) {
    var event = events.create(producer.get(), request);
    var location = UriBuilder.fromResource(EventResource.class).path(event.id().toString()).build();
    return Response.created(location).entity(event).build();
  }

  @GET
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "List events, newest first",
      description =
          "The event inbox: events ordered by createdAt, newest first (ties broken by id), one"
              + " page at a time. Filters combine with AND; repeating a filter parameter matches"
              + " any of its values. To read the next page, repeat the request with the same"
              + " filters and cursor set to the previous page's nextCursor. Events published"
              + " after the first page never shift or repeat entries on later pages; they appear"
              + " when the listing is started again. Requires a client key or the admin token.")
  @APIResponse(
      responseCode = "200",
      description = "A page of events.",
      content = @Content(schema = @Schema(implementation = EventPage.class)))
  @APIResponse(
      responseCode = "400",
      description = "A query parameter is invalid. Each violation names the parameter.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key or admin token.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public EventPage list(
      @Parameter(
              description = "Only events of this producer (canonical ID). Repeatable.",
              schema = @Schema(type = SchemaType.ARRAY, implementation = UUID.class))
          @QueryParam("producerId")
          List<String> producerIds,
      @Parameter(
              description = "Only events with this category. Repeatable.",
              schema = @Schema(type = SchemaType.ARRAY, implementation = Category.class))
          @QueryParam("category")
          List<String> categories,
      @Parameter(
              description = "Only events with this severity. Repeatable.",
              schema = @Schema(type = SchemaType.ARRAY, implementation = Severity.class))
          @QueryParam("severity")
          List<String> severities,
      @Parameter(
              description =
                  "Only events created at or after this time (inclusive). ISO-8601 with a UTC"
                      + " offset; URL-encode a + offset as %2B.",
              example = "2026-09-25T00:00:00Z",
              schema = @Schema(type = SchemaType.STRING, format = "date-time"))
          @QueryParam("createdFrom")
          String createdFrom,
      @Parameter(
              description =
                  "Only events created before this time (exclusive). ISO-8601 with a UTC offset.",
              example = "2026-09-26T00:00:00Z",
              schema = @Schema(type = SchemaType.STRING, format = "date-time"))
          @QueryParam("createdBefore")
          String createdBefore,
      @Parameter(
              description = "The nextCursor of the previous page. Omit for the first page.",
              schema = @Schema(type = SchemaType.STRING))
          @QueryParam("cursor")
          String cursor,
      @Parameter(
              description =
                  "Maximum number of events on the page, 1 to "
                      + EventQuery.MAX_LIMIT
                      + ". Defaults to "
                      + EventQuery.DEFAULT_LIMIT
                      + ".",
              schema =
                  @Schema(
                      type = SchemaType.INTEGER,
                      minimum = "1",
                      maximum = "100",
                      defaultValue = "50"))
          @QueryParam("limit")
          String limit) {
    return events.list(
        EventQuery.parse(
            producerIds, categories, severities, createdFrom, createdBefore, cursor, limit));
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Get an event by its canonical ID")
  @APIResponse(
      responseCode = "200",
      description = "The event.",
      content = @Content(schema = @Schema(implementation = EventResponse.class)))
  @APIResponse(
      responseCode = "404",
      description = "No event has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public EventResponse get(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id) {
    return events.find(id).orElseThrow(EventResource::eventNotFound);
  }

  @GET
  @Path("/unread-count")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Count unread events",
      description =
          "How many events the owner has not marked read. Requires a client key or the admin"
              + " token.")
  @APIResponse(
      responseCode = "200",
      description = "The unread count.",
      content = @Content(schema = @Schema(implementation = UnreadCount.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key or admin token.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public UnreadCount unreadCount() {
    return events.countUnread();
  }

  @PUT
  @Path("/{id}/read")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Mark an event read",
      description =
          "Marks the event read for all of the owner's clients. Idempotent: marking a read event"
              + " again keeps its readAt. Requires a client key or the admin token.")
  @APIResponse(
      responseCode = "200",
      description = "The event, now read.",
      content = @Content(schema = @Schema(implementation = EventResponse.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key or admin token.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No event has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public EventResponse markRead(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id) {
    return events.markRead(id).orElseThrow(EventResource::eventNotFound);
  }

  @DELETE
  @Path("/{id}/read")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Mark an event unread",
      description =
          "Marks the event unread again for all of the owner's clients. Idempotent. Requires a"
              + " client key or the admin token.")
  @APIResponse(
      responseCode = "200",
      description = "The event, now unread.",
      content = @Content(schema = @Schema(implementation = EventResponse.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key or admin token.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No event has this ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public EventResponse markUnread(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id) {
    return events.markUnread(id).orElseThrow(EventResource::eventNotFound);
  }

  @POST
  @Path("/read")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Mark events read up to one",
      description =
          "Marks read every unread event at or before the given event in listing order (the"
              + " given event and everything older). Events stored after it stay unread, so"
              + " passing the newest event a client shows never marks events it has not shown."
              + " Requires a client key or the admin token.")
  @APIResponse(
      responseCode = "200",
      description = "How many events were marked read.",
      content = @Content(schema = @Schema(implementation = MarkReadResult.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key or admin token.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No event has the ID given as through.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public MarkReadResult markReadThrough(@NotNull @Valid MarkReadRequest request) {
    return events.markReadThrough(request.through()).orElseThrow(EventResource::eventNotFound);
  }

  private static NotFoundException eventNotFound() {
    return new NotFoundException(
        Response.status(Response.Status.NOT_FOUND)
            .entity(new ApiError("Event not found", 404, List.of()))
            .build());
  }

  private static final String CI_EXAMPLE =
      """
      {
        "context": "signalhub",
        "category": "BLOCKED",
        "severity": "HIGH",
        "title": "Nightly build failed",
        "message": "3 of 412 tests failed on main.",
        "metadata": {"pipeline": "nightly", "run": 1842, "url": "https://ci.example.com/runs/1842"},
        "occurredAt": "2026-09-25T14:03:00+02:00"
      }
      """;

  private static final String AGENT_EXAMPLE =
      """
      {
        "context": "repo:example/app",
        "category": "ACTION_REQUIRED",
        "severity": "NORMAL",
        "title": "Plan ready for review",
        "message": "The agent finished planning and is waiting for approval.",
        "metadata": {"workflowId": "wf-73", "step": "plan", "reviewUrl": "https://example.com/wf-73"}
      }
      """;

  private static final String MINIMAL =
      """
      {"category": "COMPLETED", "severity": "LOW", "title": "Backup done"}
      """;
}
