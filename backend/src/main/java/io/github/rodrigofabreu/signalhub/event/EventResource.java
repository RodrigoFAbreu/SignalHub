package io.github.rodrigofabreu.signalhub.event;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.api.QuestionState;
import io.github.rodrigofabreu.signalhub.client.AuthenticatedClient;
import io.github.rodrigofabreu.signalhub.client.ClientIdentity;
import io.github.rodrigofabreu.signalhub.client.ClientResource;
import io.github.rodrigofabreu.signalhub.client.OwnerAuthenticated;
import io.github.rodrigofabreu.signalhub.producer.AuthenticatedProducer;
import io.github.rodrigofabreu.signalhub.producer.ProducerAdminResource;
import io.github.rodrigofabreu.signalhub.producer.ProducerAuthenticated;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.runtime.Startup;
import io.smallrye.common.annotation.RunOnVirtualThread;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.Valid;
import jakarta.validation.Validator;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.HeaderParam;
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
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Pattern;
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
// Created at startup so its meter is scraped before the first event.
@Startup
public class EventResource {

  static final String SECURITY_SCHEME = "producerApiKey";
  static final String IDEMPOTENCY_KEY = "Idempotency-Key";

  // Visible ASCII: a key must survive any HTTP client and proxy unchanged.
  private static final Pattern IDEMPOTENCY_KEY_FORMAT = Pattern.compile("[!-~]{1,200}");

  private final EventService events;
  private final AuthenticatedProducer producer;
  private final AuthenticatedClient client;
  private final UserDirectory userDirectory;
  private final QuestionService questions;
  private final AnswerWaits waits;
  private final ObjectMapper json;
  private final Validator validator;
  private final Counter published;

  EventResource(
      EventService events,
      AuthenticatedProducer producer,
      AuthenticatedClient client,
      UserDirectory userDirectory,
      QuestionService questions,
      AnswerWaits waits,
      ObjectMapper json,
      Validator validator,
      MeterRegistry registry) {
    this.events = events;
    this.json = json;
    this.validator = validator;
    this.questions = questions;
    this.waits = waits;
    this.userDirectory = userDirectory;
    this.producer = producer;
    this.client = client;
    // Untagged: producer names are the owner's data, and categories or severities are in the
    // inbox already.
    this.published =
        Counter.builder("signalhub.events.published")
            .description("Events stored and acknowledged")
            .register(registry);
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
              + " createdAt. With an Idempotency-Key the producer already sent, nothing is"
              + " stored: the answer is 200 with the event stored then, so a request whose answer"
              + " was lost can be sent again without storing a duplicate.")
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
      responseCode = "200",
      description =
          "The producer already published this event with this Idempotency-Key; nothing new was"
              + " stored. The body is the event as it is stored now, and the Location header"
              + " points to it.",
      content = @Content(schema = @Schema(implementation = EventResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body or the Idempotency-Key header is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "422",
      description =
          "The producer already used this Idempotency-Key for a different event. Nothing was"
              + " stored.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "401",
      description =
          "Missing, malformed, unknown or revoked API key, or the producer is disabled. The"
              + " response does not say which.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "413",
      description = "The body is larger than 64 KiB. The HTTP layer refuses it without a body.")
  @APIResponse(
      responseCode = "415",
      description = "The body is not JSON.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(
      @Parameter(
              description =
                  "Optional key, unique per producer, that makes publishing idempotent: sending"
                      + " the same event with the same key again stores nothing and answers the"
                      + " stored event. 1 to 200 visible ASCII characters, such as a UUID. Free"
                      + " again once its event is deleted by retention.",
              example = "ci-nightly-1842",
              schema = @Schema(type = SchemaType.STRING, minLength = 1, maxLength = 200))
          @HeaderParam(IDEMPOTENCY_KEY)
          String idempotencyKey,
      @NotNull @Valid CreateEventRequest request) {
    validateIdempotencyKey(idempotencyKey);
    var result = events.create(producer.get(), request, idempotencyKey);
    var event = result.event();
    var location = UriBuilder.fromResource(EventResource.class).path(event.id().toString()).build();
    if (!result.created()) {
      return Response.ok(event).location(location).build();
    }
    // Counted once committed: create returns only after the transaction.
    published.increment();
    return Response.created(location).entity(event).build();
  }

  private static void validateIdempotencyKey(String key) {
    if (key != null && !IDEMPOTENCY_KEY_FORMAT.matcher(key).matches()) {
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(
                  new ApiError(
                      "Invalid request",
                      400,
                      List.of(
                          new ApiError.Violation(
                              IDEMPOTENCY_KEY,
                              "must be 1 to 200 visible ASCII characters, without spaces"))))
              .build());
    }
  }

  @GET
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "List events, newest first",
      description =
          "The event inbox: the events of the producers the caller's user is subscribed to,"
              + " ordered by createdAt, newest first (ties broken by id), one"
              + " page at a time. Filters combine with AND; repeating a filter parameter matches"
              + " any of its values. To read the next page, repeat the request with the same"
              + " filters and cursor set to the previous page's nextCursor. Events published"
              + " after the first page never shift or repeat entries on later pages; they appear"
              + " when the listing is started again. Requires a client key, which lists its user's"
              + " events, or the admin token, which lists every event and may also filter by"
              + " user (userId, relation): the events of the producers that user owns or is"
              + " subscribed to, by how their pushes went (push), and may ask for the number of"
              + " matching events (total). Its events each carry push, a summary of their delivery"
              + " records.")
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
  @APIResponse(
      responseCode = "404",
      description = "No user has the userId given.",
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
                  "Only unread events (false) or only read events (true). Omit for both. Unread"
                      + " events are the ones without readAt.",
              schema = @Schema(type = SchemaType.BOOLEAN))
          @QueryParam("read")
          String read,
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
              description =
                  "Only events of the producers this user owns or is subscribed to (canonical"
                      + " user ID), revoked users included. Admin token only: a client key is"
                      + " refused with 400.",
              schema = @Schema(type = SchemaType.STRING, format = "uuid"))
          @QueryParam("userId")
          String userId,
      @Parameter(
              description =
                  "With userId: only the producers the user owns (OWNED) or is subscribed to"
                      + " (SUBSCRIBED). Omit for either.",
              schema = @Schema(implementation = UserRelation.class))
          @QueryParam("relation")
          String relation,
      @Parameter(
              description =
                  "Only events whose pushes went as this says: GAVE_UP, FAILED, WAITING_FOR_RETRY,"
                      + " SENT, NOT_SENT, PENDING or NOBODY_TO_REACH (see each event's push)."
                      + " Repeatable: push=FAILED&push=GAVE_UP lists the events with a push"
                      + " problem. Admin token only: a client key is refused with 400.",
              schema = @Schema(type = SchemaType.ARRAY, implementation = PushSummary.class))
          @QueryParam("push")
          List<String> push,
      @Parameter(
              description =
                  "With true, only the open questions the caller may answer: events that ask,"
                      + " that nobody answered or closed, whose closesAt has not passed, on"
                      + " producers the caller owns or may answer. Only true is accepted. Read"
                      + " or not. With the admin token, who answers nothing, the list is empty.",
              schema = @Schema(type = SchemaType.BOOLEAN))
          @QueryParam("toAnswer")
          String toAnswer,
      @Parameter(
              description =
                  "Only events whose question stands as this says: OPEN, ANSWERED, CLOSED, or"
                      + " NONE for events that ask nothing. Repeatable. Admin token only: a"
                      + " client key is refused with 400.",
              schema = @Schema(type = SchemaType.ARRAY, implementation = AnswerFilter.class))
          @QueryParam("answerState")
          List<String> answerStates,
      @Parameter(
              description =
                  "With true, the page also says how many events match the filters in all"
                      + " (total). Counting walks every matching event, so ask only when the number"
                      + " is shown. Admin token only: a client key is refused with 400.",
              schema = @Schema(type = SchemaType.BOOLEAN, defaultValue = "false"))
          @QueryParam("total")
          String total,
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
    var query =
        EventQuery.parse(
            producerIds,
            categories,
            severities,
            read,
            createdFrom,
            createdBefore,
            userId,
            relation,
            push,
            toAnswer,
            answerStates,
            total,
            cursor,
            limit);
    checkAdminOnly(query);
    checkUserFilter(query);
    return events.list(query, user());
  }

  /** How events' pushes went, their question states and the total are the operator's. */
  private void checkAdminOnly(EventQuery query) {
    if (user().isEmpty()) {
      return;
    }
    var violations = new ArrayList<ApiError.Violation>();
    if (!query.push().isEmpty()) {
      violations.add(new ApiError.Violation("push", "is available with the admin token only"));
    }
    if (!query.answerStates().isEmpty()) {
      violations.add(
          new ApiError.Violation("answerState", "is available with the admin token only"));
    }
    if (query.total()) {
      violations.add(new ApiError.Violation("total", "is available with the admin token only"));
    }
    if (!violations.isEmpty()) {
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(new ApiError("Invalid request", 400, violations))
              .build());
    }
  }

  /**
   * The per-user view is the operator's: a client key may not ask for another user's events, and
   * the user must exist.
   */
  private void checkUserFilter(EventQuery query) {
    if (query.userId().isEmpty() && query.relation().isEmpty()) {
      return;
    }
    if (user().isPresent() || query.userId().isEmpty()) {
      var field = query.userId().isEmpty() ? "relation" : "userId";
      var message =
          user().isPresent() ? "is available with the admin token only" : "needs a userId";
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(
                  new ApiError(
                      "Invalid request", 400, List.of(new ApiError.Violation(field, message))))
              .build());
    }
    if (userDirectory.find(query.userId().get()).isEmpty()) {
      throw new NotFoundException(
          Response.status(Response.Status.NOT_FOUND)
              .entity(new ApiError("User not found", 404, List.of()))
              .build());
    }
  }

  @GET
  @Path("/{id}")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Get an event by its canonical ID",
      description =
          "Requires a client key or the admin token. A client key reads only events of the"
              + " producers its user is subscribed to; any other event is 404, as if it did not"
              + " exist. The admin token reads every event.")
  @APIResponse(
      responseCode = "200",
      description = "The event.",
      content = @Content(schema = @Schema(implementation = EventResponse.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key or admin token.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No event has this ID, or the caller's user does not receive it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public EventResponse get(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id) {
    return events.find(id, user()).orElseThrow(EventResource::eventNotFound);
  }

  @GET
  @Path("/unread-count")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Count unread events",
      description =
          "How many of the events the caller's user receives they have not marked read. The admin"
              + " token counts every event it has not marked read. Requires a client key or the"
              + " admin token.")
  @APIResponse(
      responseCode = "200",
      description = "The unread count.",
      content = @Content(schema = @Schema(implementation = UnreadCount.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key or admin token.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public UnreadCount unreadCount() {
    return events.countUnread(user());
  }

  @PUT
  @Path("/{id}/read")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Mark an event read",
      description =
          "Marks the event read for all of the caller's user's devices, and no one else's."
              + " Idempotent: marking a read event again keeps its readAt. Requires a client key"
              + " or the admin token (the operator's own read state).")
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
      description = "No event has this ID, or the caller's user does not receive it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public EventResponse markRead(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id) {
    return events.markRead(id, user()).orElseThrow(EventResource::eventNotFound);
  }

  @DELETE
  @Path("/{id}/read")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Mark an event unread",
      description =
          "Marks the event unread again for all of the caller's user's devices. Idempotent."
              + " Requires a client key or the admin token (the operator's own read state).")
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
      description = "No event has this ID, or the caller's user does not receive it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public EventResponse markUnread(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id) {
    return events.markUnread(id, user()).orElseThrow(EventResource::eventNotFound);
  }

  @POST
  @Path("/read")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
  @Operation(
      summary = "Mark events read up to one",
      description =
          "Marks read every unread event the caller's user receives at or before the given event"
              + " in listing order (the given event and everything older). Events stored after it stay unread, so"
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
      description =
          "No event has the ID given as through, or the caller's user does not receive it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public MarkReadResult markReadThrough(@NotNull @Valid MarkReadRequest request) {
    return events
        .markReadThrough(request.through(), user())
        .orElseThrow(EventResource::eventNotFound);
  }

  @PUT
  @Path("/{id}/answer")
  @OwnerAuthenticated
  @SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Answer the question of an event",
      description =
          "Records the caller's user's answer to the event's question: the choices and/or text"
              + " the question asks for. Only the producer's owner and its answerers may answer,"
              + " and only events in the caller's inbox. The first accepted answer wins and ends"
              + " the question for everyone; the same person sending the same answer again also"
              + " gets 200. Requires a client key or a browser's session; the admin token acts"
              + " for no user and is refused.")
  @APIResponse(
      responseCode = "200",
      description = "The accepted answer.",
      content = @Content(schema = @Schema(implementation = QuestionState.Answer.class)))
  @APIResponse(
      responseCode = "400",
      description =
          "The answer does not fit the question: an unknown or repeated choice, the wrong number"
              + " of choices, or text missing, not allowed or too long. Each violation names the"
              + " field.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing or invalid client key, or a producer's API key.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "403",
      description =
          "The admin token, or a user who may not answer this producer's questions (or a"
              + " browser request refused for its CSRF check).",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No such event in the caller's inbox: it is deleted or not subscribed to.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description =
          "The question is answered by someone else or differently, or closed (by its closesAt"
              + " or its producer), or the event asks nothing. The body's question says where it"
              + " stands: who answered what, or who closed it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public QuestionState.Answer answer(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id,
      @NotNull @Valid AnswerRequest request) {
    var caller = client.current();
    if (caller.isEmpty()) {
      throw error(Response.Status.FORBIDDEN, "The admin token answers nothing", null);
    }
    return switch (questions.answer(id, caller.get(), request)) {
      case QuestionService.Answering.Accepted accepted -> accepted.answer();
      case QuestionService.Answering.NotFound notFound -> throw eventNotFound();
      case QuestionService.Answering.Forbidden forbidden ->
          throw error(
              Response.Status.FORBIDDEN, "You may not answer this producer's questions", null);
      case QuestionService.Answering.Invalid invalid ->
          throw new BadRequestException(
              Response.status(Response.Status.BAD_REQUEST)
                  .entity(new ApiError("Invalid request", 400, invalid.violations()))
                  .build());
      case QuestionService.Answering.Conflict conflict ->
          throw conflict.state() == null
              ? error(Response.Status.CONFLICT, "The event asks nothing", null)
              : error(
                  Response.Status.CONFLICT,
                  conflict.state().state() == QuestionState.State.ANSWERED
                      ? "The question is already answered"
                      : "The question is closed",
                  conflict.state());
    };
  }

  @GET
  @Path("/{id}/answer")
  @ProducerAuthenticated
  @RunOnVirtualThread
  @SecurityRequirement(name = SECURITY_SCHEME)
  @Operation(
      summary = "Read the answer to an event's question",
      description =
          "The producer reads how its event's question stands: OPEN, ANSWERED (with the answer)"
              + " or CLOSED (by its time or by the producer). With wait, holds the request until"
              + " the state leaves OPEN or the wait ends, and returns the state then; ask again"
              + " to wait longer. Only the producer's own events, with any of its keys.")
  @APIResponse(
      responseCode = "200",
      description = "The state of the question.",
      content = @Content(schema = @Schema(implementation = QuestionState.class)))
  @APIResponse(
      responseCode = "400",
      description = "wait is not a whole number from 0 to 60.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing, malformed, unknown or revoked API key, or the producer is disabled.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No such event of this producer, or it was deleted, also while waiting.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "The event asks nothing.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public QuestionState readAnswer(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id,
      @Parameter(
              description =
                  "Seconds to wait for the question to be answered or closed: 0 (the default) to"
                      + " 60.",
              schema =
                  @Schema(
                      type = SchemaType.INTEGER,
                      minimum = "0",
                      maximum = "60",
                      defaultValue = "0"))
          @QueryParam("wait")
          String wait) {
    var seconds = parseWait(wait);
    return switch (waits.read(id, producer.get().id(), seconds)) {
      case QuestionService.Reading.Found found -> found.state();
      case QuestionService.Reading.NotFound notFound -> throw eventNotFound();
      case QuestionService.Reading.NoQuestion noQuestion ->
          throw error(Response.Status.CONFLICT, "The event asks nothing", null);
    };
  }

  private static int parseWait(String text) {
    if (text == null) {
      return 0;
    }
    try {
      var seconds = Integer.parseInt(text);
      if (seconds >= 0 && seconds <= AnswerWaits.MAX_WAIT_SECONDS) {
        return seconds;
      }
    } catch (NumberFormatException e) {
      // Reported below.
    }
    throw new BadRequestException(
        Response.status(Response.Status.BAD_REQUEST)
            .entity(
                new ApiError(
                    "Invalid request",
                    400,
                    List.of(
                        new ApiError.Violation(
                            "wait",
                            "must be a whole number of seconds from 0 to "
                                + AnswerWaits.MAX_WAIT_SECONDS))))
            .build());
  }

  @POST
  @Path("/{id}/answer/close")
  @Consumes(MediaType.WILDCARD)
  @ProducerAuthenticated
  @SecurityRequirement(name = SECURITY_SCHEME)
  @Operation(
      summary = "Close an event's question",
      description =
          "The producer closes its question without an answer, for one answered somewhere else."
              + " Nobody can answer it afterwards, and the devices it reached are told. Closing"
              + " again keeps the first close's note and time; closing after closesAt also"
              + " succeeds (closedBy TIME). The body is optional. Only the producer's own events.")
  @APIResponse(
      responseCode = "200",
      description = "The question is closed, now or before.",
      content = @Content(schema = @Schema(implementation = QuestionState.class)))
  @APIResponse(
      responseCode = "400",
      description = "The note is blank, too long or holds a NUL character.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "401",
      description = "Missing, malformed, unknown or revoked API key, or the producer is disabled.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No such event of this producer, or it was deleted.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description =
          "Someone answered first (the body's question carries that answer), or the event asks"
              + " nothing.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public QuestionState closeQuestion(
      @Parameter(description = "Canonical event ID (UUID).") @PathParam("id") UUID id,
      @RequestBody(
              content =
                  @Content(
                      mediaType = MediaType.APPLICATION_JSON,
                      schema = @Schema(implementation = CloseQuestionRequest.class)))
          String body)
      throws JsonProcessingException {
    var note = closeNote(body);
    return switch (questions.close(id, producer.get().id(), note)) {
      case QuestionService.Closing.Closed closed -> closed.state();
      case QuestionService.Closing.Answered answered ->
          throw error(
              Response.Status.CONFLICT, "The question is already answered", answered.state());
      case QuestionService.Closing.NotFound notFound -> throw eventNotFound();
      case QuestionService.Closing.NoQuestion noQuestion ->
          throw error(Response.Status.CONFLICT, "The event asks nothing", null);
    };
  }

  /**
   * The note of the optional JSON body. Read here rather than bound, so a close with no body at all
   * (no Content-Type either) is as good as one with {@code {}}.
   */
  private String closeNote(String body) throws JsonProcessingException {
    if (body == null || body.isBlank()) {
      return null;
    }
    var request = json.readValue(body, CloseQuestionRequest.class);
    if (request == null) {
      return null;
    }
    var violations = validator.validate(request);
    if (!violations.isEmpty()) {
      throw new ConstraintViolationException(violations);
    }
    return request.note();
  }

  private static ClientErrorException error(
      Response.Status status, String title, QuestionState question) {
    return new ClientErrorException(
        Response.status(status)
            .entity(new ApiError(title, status.getStatusCode(), List.of(), question))
            .build());
  }

  /** The user whose events are read; empty for the operator, who reads them all. */
  private Optional<UUID> user() {
    return client.current().map(ClientIdentity::userId);
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
        "metadata": {"pipeline": "nightly", "run": 1842},
        "link": "https://ci.example.com/runs/1842",
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
