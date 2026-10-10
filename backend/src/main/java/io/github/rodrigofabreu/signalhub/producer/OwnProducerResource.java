package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.client.AuthenticatedClient;
import io.github.rodrigofabreu.signalhub.client.ClientAuthenticated;
import io.github.rodrigofabreu.signalhub.client.ClientResource;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.PATCH;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.PUT;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import jakarta.ws.rs.core.UriBuilder;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * A user's own producers, from their device: register, list with keys by prefix, issue and revoke
 * keys, disable and enable, rename, set the visibility and the allow-list. Under {@code
 * /api/v1/client}, so the proxy forwards it. Open to every role; every operation reaches only
 * producers the caller's user owns, and another user's producer is {@code 404}, as if it did not
 * exist.
 */
@Path("/api/v1/client/producers")
@Tag(
    name = "Own producers",
    description =
        "The producers the caller's user owns, managed from a device with its client key. Open to"
            + " every role. A producer owned by anyone else, an admin's included, is 404. A key is"
            + " shown only in the answer that issues it.")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class OwnProducerResource {

  private final ProducerService producers;
  private final AuthenticatedClient caller;

  OwnProducerResource(ProducerService producers, AuthenticatedClient caller) {
    this.producers = producers;
    this.caller = caller;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Register a producer",
      description =
          "Creates a producer owned by the caller's user, private unless made public, and its"
              + " first API key, which is shown only in this answer. The owner is subscribed to"
              + " it. The producer publishes with the key (POST /api/v1/events).")
  @APIResponse(
      responseCode = "201",
      description = "Producer created. The Location header points to it.",
      content = @Content(schema = @Schema(implementation = IssuedOwnApiKey.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "A producer with this name exists, or the caller's user was revoked.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateOwnProducerRequest request) {
    return switch (producers.createOwn(userId(), request.name(), request.visibilityOrDefault())) {
      case ProducerService.OwnCreate.Created created -> {
        var location = UriBuilder.fromResource(OwnProducerResource.class).path("{id}");
        yield Response.created(location.build(created.key().producer().id()))
            .entity(created.key())
            .build();
      }
      case ProducerService.OwnCreate.NameTaken taken -> throw nameTaken();
      case ProducerService.OwnCreate.OwnerRevoked revoked -> throw conflict("User is revoked");
    };
  }

  @GET
  @Operation(
      summary = "List own producers",
      description = "The producers the caller's user owns, by name, with their keys by prefix.")
  @APIResponse(
      responseCode = "200",
      description = "The producers, in items.",
      content = @Content(schema = @Schema(implementation = OwnProducerList.class)))
  public OwnProducerList list() {
    return new OwnProducerList(producers.listOwn(userId()));
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Get an own producer")
  @APIResponse(
      responseCode = "200",
      description = "The producer.",
      content = @Content(schema = @Schema(implementation = OwnProducerResponse.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not own it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public OwnProducerResponse get(@PathParam("id") UUID id) {
    return orNotFound(producers.getOwn(userId(), id));
  }

  @PATCH
  @Path("/{id}")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Rename a producer or change who sees it",
      description =
          "Sets the producer's name, its visibility, or both. Its keys keep working and its"
              + " events stay its own. A subscriber who no longer sees a private producer (neither"
              + " its owner nor allowed) is unsubscribed.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, changed.",
      content = @Content(schema = @Schema(implementation = OwnProducerResponse.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed, fails validation or changes nothing.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not own it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "Another producer has this name.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public OwnProducerResponse update(
      @PathParam("id") UUID id, @NotNull @Valid UpdateOwnProducerRequest request) {
    if (request.changesNothing()) {
      throw new BadRequestException(
          Response.status(Response.Status.BAD_REQUEST)
              .entity(
                  new ApiError(
                      "Invalid request",
                      400,
                      List.of(new ApiError.Violation("", "must give name, visibility or both"))))
              .build());
    }
    return changed(producers.updateOwn(userId(), id, request.name(), request.visibility()));
  }

  @POST
  @Path("/{id}/keys")
  @Operation(
      summary = "Issue an API key",
      description =
          "Issues an additional key, shown only in this answer. Existing keys stay valid, so a key"
              + " is rotated by issuing a new one, switching the producer to it, and revoking the"
              + " old one. The request has no body.")
  @APIResponse(
      responseCode = "201",
      description = "Key issued.",
      content = @Content(schema = @Schema(implementation = IssuedOwnApiKey.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not own it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response issueKey(@PathParam("id") UUID id) {
    var issued = orNotFound(producers.issueOwnKey(userId(), id));
    return Response.status(Response.Status.CREATED).entity(issued).build();
  }

  @POST
  @Path("/{id}/keys/{keyId}/revoke")
  @Operation(
      summary = "Revoke an API key",
      description =
          "The key stops authenticating immediately and permanently. Revoking a revoked key"
              + " changes nothing. The request has no body.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, with the key revoked.",
      content = @Content(schema = @Schema(implementation = OwnProducerResponse.class)))
  @APIResponse(
      responseCode = "404",
      description =
          "No producer has this ID, the caller's user does not own it, or it has no such key.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public OwnProducerResponse revokeKey(@PathParam("id") UUID id, @PathParam("keyId") UUID keyId) {
    return orNotFound(producers.revokeOwnKey(userId(), id, keyId));
  }

  @POST
  @Path("/{id}/disable")
  @Operation(
      summary = "Disable a producer",
      description =
          "None of the producer's keys authenticate until it is enabled again. Its events are"
              + " kept. Disabling a disabled producer changes nothing. The request has no body.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, now disabled.",
      content = @Content(schema = @Schema(implementation = OwnProducerResponse.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not own it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public OwnProducerResponse disable(@PathParam("id") UUID id) {
    return changed(producers.disableOwn(userId(), id));
  }

  @POST
  @Path("/{id}/enable")
  @Operation(
      summary = "Enable a producer",
      description =
          "Its keys that are not revoked authenticate again. A producer the operator disabled, or"
              + " disabled because its owner was revoked, stays disabled: only the operator"
              + " enables it. The request has no body.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, now enabled.",
      content = @Content(schema = @Schema(implementation = OwnProducerResponse.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not own it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description = "The operator disabled the producer.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public OwnProducerResponse enable(@PathParam("id") UUID id) {
    return changed(producers.enableOwn(userId(), id));
  }

  @PUT
  @Path("/{id}/allowed-users/{userId}")
  @Operation(
      summary = "Allow a user on a producer",
      description =
          "Puts a user on the producer's allow-list, so they see it while it is private and may"
              + " subscribe; they are not subscribed by this. Allowing an allowed user, or the"
              + " owner, changes nothing. The request has no body.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, with its allow-list.",
      content = @Content(schema = @Schema(implementation = OwnProducerResponse.class)))
  @APIResponse(
      responseCode = "404",
      description =
          "No producer has this ID, the caller's user does not own it, or no user who is not"
              + " revoked has the user ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public OwnProducerResponse allow(@PathParam("id") UUID id, @PathParam("userId") UUID userId) {
    return changed(producers.allowOwn(userId(), id, userId));
  }

  @DELETE
  @Path("/{id}/allowed-users/{userId}")
  @Operation(
      summary = "Take a user off a producer's allow-list",
      description =
          "The user no longer sees the producer while it is private, and their subscription to it"
              + " ends. Removing a user who is not on the list changes nothing.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, with its allow-list.",
      content = @Content(schema = @Schema(implementation = OwnProducerResponse.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not own it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public OwnProducerResponse disallow(@PathParam("id") UUID id, @PathParam("userId") UUID userId) {
    return changed(producers.disallowOwn(userId(), id, userId));
  }

  private UUID userId() {
    return caller.get().userId();
  }

  private static OwnProducerResponse changed(Optional<ProducerService.OwnChange> result) {
    return switch (orNotFound(result)) {
      case ProducerService.OwnChange.Updated updated -> updated.producer();
      case ProducerService.OwnChange.NameTaken taken -> throw nameTaken();
      case ProducerService.OwnChange.DisabledByOperator operator ->
          throw conflict("The operator disabled this producer");
      case ProducerService.OwnChange.UnknownUser unknown -> throw notFound();
    };
  }

  private static ClientErrorException nameTaken() {
    return new ClientErrorException(
        Response.status(Response.Status.CONFLICT)
            .entity(
                new ApiError(
                    "Producer name already exists",
                    409,
                    List.of(new ApiError.Violation("name", "is already taken"))))
            .build());
  }

  private static ClientErrorException conflict(String title) {
    return new ClientErrorException(
        Response.status(Response.Status.CONFLICT)
            .entity(new ApiError(title, 409, List.of()))
            .build());
  }

  private static NotFoundException notFound() {
    return new NotFoundException(
        Response.status(Response.Status.NOT_FOUND)
            .entity(new ApiError("Not found", 404, List.of()))
            .build());
  }

  private static <T> T orNotFound(Optional<T> result) {
    return result.orElseThrow(OwnProducerResource::notFound);
  }
}
