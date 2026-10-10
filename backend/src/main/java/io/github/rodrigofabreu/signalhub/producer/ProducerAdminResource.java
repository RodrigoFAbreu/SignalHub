package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.ws.rs.BadRequestException;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.PATCH;
import jakarta.ws.rs.POST;
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
import org.eclipse.microprofile.openapi.annotations.enums.SecuritySchemeType;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.security.SecurityScheme;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * Producer management for the operator: register producers, issue and revoke their keys, disable
 * them. Requires the admin token, and does not exist unless one is configured.
 */
@Path("/api/v1/admin/producers")
@Tag(
    name = "Producer management",
    description =
        "Register producers and manage their API keys. Requires the admin token"
            + " (SIGNALHUB_ADMIN_TOKEN); every path answers 404 when none is configured.")
@SecurityScheme(
    securitySchemeName = ProducerAdminResource.SECURITY_SCHEME,
    type = SecuritySchemeType.HTTP,
    scheme = "bearer",
    description = "The operator's admin token, configured with SIGNALHUB_ADMIN_TOKEN.")
@SecurityRequirement(name = ProducerAdminResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description = "Missing or wrong admin token.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@AdminOnly
@Produces(MediaType.APPLICATION_JSON)
public class ProducerAdminResource {

  public static final String SECURITY_SCHEME = "adminToken";

  private final ProducerService producers;
  private final UserDirectory users;

  ProducerAdminResource(ProducerService producers, UserDirectory users) {
    this.producers = producers;
    this.users = users;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Register a producer",
      description =
          "Creates the producer, owned by the given user (the oldest admin who is not revoked when"
              + " none is given) and private unless made public, and its first API key, which is"
              + " shown only once. The owner is subscribed to it.")
  @APIResponse(
      responseCode = "201",
      description = "Producer created. The Location header points to it.",
      content = @Content(schema = @Schema(implementation = IssuedApiKey.class)))
  @APIResponse(
      responseCode = "400",
      description = "The body is malformed or fails validation.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "404",
      description = "No user has the given owner ID.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "409",
      description =
          "A producer with this name exists, or the owner is revoked, or none is given and no"
              + " admin is available.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Response create(@NotNull @Valid CreateProducerRequest request) {
    var owner = ownerOf(request.ownerId());
    var issued =
        producers
            .create(request.name(), owner, request.visibilityOrDefault())
            .orElseThrow(
                () ->
                    new ClientErrorException(
                        Response.status(Response.Status.CONFLICT)
                            .entity(
                                new ApiError(
                                    "Producer name already exists",
                                    409,
                                    List.of(new ApiError.Violation("name", "is already taken"))))
                            .build()));
    var location = UriBuilder.fromResource(ProducerAdminResource.class).path("{id}");
    return Response.created(location.build(issued.producer().id())).entity(issued).build();
  }

  @GET
  @Operation(summary = "List producers", description = "All producers and their keys, by name.")
  @APIResponse(
      responseCode = "200",
      description = "The producers, in items.",
      content = @Content(schema = @Schema(implementation = ProducerList.class)))
  public ProducerList list() {
    return new ProducerList(producers.list());
  }

  @GET
  @Path("/{id}")
  @Operation(summary = "Get a producer and its keys")
  @APIResponse(
      responseCode = "200",
      description = "The producer.",
      content = @Content(schema = @Schema(implementation = ProducerResponse.class)))
  @APIResponse(responseCode = "404", description = "No producer has this ID.")
  public ProducerResponse get(@PathParam("id") UUID id) {
    return orNotFound(producers.get(id));
  }

  @PATCH
  @Path("/{id}")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Change who sees a producer",
      description =
          "Sets the producer's visibility, replaces its allow-list, or both. A subscriber who"
              + " no longer sees a private producer (neither its owner nor allowed) is"
              + " unsubscribed.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, changed.",
      content = @Content(schema = @Schema(implementation = ProducerResponse.class)))
  @APIResponse(
      responseCode = "400",
      description =
          "The body is malformed, changes nothing, or the allow-list names users that do not"
              + " exist or are revoked.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(responseCode = "404", description = "No producer has this ID.")
  public ProducerResponse update(
      @PathParam("id") UUID id, @NotNull @Valid UpdateProducerRequest request) {
    if (request.changesNothing()) {
      throw badRequest("", "must give visibility, allowedUserIds or both");
    }
    return switch (orNotFound(
        producers.update(id, request.visibility(), request.allowedUserIds()))) {
      case ProducerService.Update.Updated updated -> updated.producer();
      case ProducerService.Update.UnknownUsers unknown ->
          throw badRequest("allowedUserIds", "names unknown or revoked users: " + unknown.ids());
    };
  }

  @POST
  @Path("/{id}/disable")
  @Operation(
      summary = "Disable a producer",
      description =
          "None of the producer's keys authenticate until it is enabled again. Its events are"
              + " kept. Disabling a disabled producer changes nothing.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, now disabled.",
      content = @Content(schema = @Schema(implementation = ProducerResponse.class)))
  @APIResponse(responseCode = "404", description = "No producer has this ID.")
  public ProducerResponse disable(@PathParam("id") UUID id) {
    return orNotFound(producers.disable(id));
  }

  @POST
  @Path("/{id}/enable")
  @Operation(
      summary = "Enable a producer",
      description = "Its keys that are not revoked authenticate again.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, now enabled.",
      content = @Content(schema = @Schema(implementation = ProducerResponse.class)))
  @APIResponse(responseCode = "404", description = "No producer has this ID.")
  public ProducerResponse enable(@PathParam("id") UUID id) {
    return orNotFound(producers.enable(id));
  }

  @POST
  @Path("/{id}/keys")
  @Operation(
      summary = "Issue an API key",
      description =
          "Issues an additional key, shown only once. Existing keys stay valid, so a key is"
              + " rotated by issuing a new one, switching the producer to it, and revoking the"
              + " old one.")
  @APIResponse(
      responseCode = "201",
      description = "Key issued.",
      content = @Content(schema = @Schema(implementation = IssuedApiKey.class)))
  @APIResponse(responseCode = "404", description = "No producer has this ID.")
  public Response issueKey(@PathParam("id") UUID id) {
    var issued = orNotFound(producers.issueKey(id));
    return Response.status(Response.Status.CREATED).entity(issued).build();
  }

  @POST
  @Path("/{id}/keys/{keyId}/revoke")
  @Operation(
      summary = "Revoke an API key",
      description =
          "The key stops authenticating immediately and permanently. Revoking a revoked key"
              + " changes nothing.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, with the key revoked.",
      content = @Content(schema = @Schema(implementation = ProducerResponse.class)))
  @APIResponse(responseCode = "404", description = "The producer has no key with this ID.")
  public ProducerResponse revokeKey(@PathParam("id") UUID id, @PathParam("keyId") UUID keyId) {
    return orNotFound(producers.revokeKey(id, keyId));
  }

  /** The given owner, or the default one; refused if unknown, revoked or there is none. */
  private UUID ownerOf(UUID requested) {
    var owner = requested == null ? users.defaultOwner() : users.find(requested);
    if (owner.isEmpty()) {
      throw requested == null
          ? conflict("No admin to own the producer; give ownerId")
          : new NotFoundException(
              Response.status(Response.Status.NOT_FOUND)
                  .entity(new ApiError("User not found", 404, List.of()))
                  .build());
    }
    if (!users.isActive(owner.get().id())) {
      throw conflict("User is revoked");
    }
    return owner.get().id();
  }

  private static ClientErrorException conflict(String title) {
    return new ClientErrorException(
        Response.status(Response.Status.CONFLICT)
            .entity(new ApiError(title, 409, List.of()))
            .build());
  }

  private static BadRequestException badRequest(String field, String message) {
    return new BadRequestException(
        Response.status(Response.Status.BAD_REQUEST)
            .entity(
                new ApiError(
                    "Invalid request", 400, List.of(new ApiError.Violation(field, message))))
            .build());
  }

  private static <T> T orNotFound(Optional<T> result) {
    return result.orElseThrow(
        () ->
            new NotFoundException(
                Response.status(Response.Status.NOT_FOUND)
                    .entity(new ApiError("Not found", 404, List.of()))
                    .build()));
  }
}
