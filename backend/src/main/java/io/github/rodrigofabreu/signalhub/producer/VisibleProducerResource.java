package io.github.rodrigofabreu.signalhub.producer;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.client.AuthenticatedClient;
import io.github.rodrigofabreu.signalhub.client.ClientAuthenticated;
import io.github.rodrigofabreu.signalhub.client.ClientResource;
import jakarta.ws.rs.DELETE;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.NotFoundException;
import jakarta.ws.rs.PUT;
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
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * The producers a user can see, and their subscriptions to them, from their device. Open to every
 * role. A producer the user does not see is {@code 404}, exactly like one that does not exist.
 */
@Path("/api/v1/client/visible-producers")
@Tag(
    name = "Subscriptions",
    description =
        "The producers the caller's user sees (public ones, their own, and private ones they are"
            + " allowed on) and which of them they receive events from. Open to every role.")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class VisibleProducerResource {

  private final ProducerService producers;
  private final AuthenticatedClient caller;

  VisibleProducerResource(ProducerService producers, AuthenticatedClient caller) {
    this.producers = producers;
    this.caller = caller;
  }

  @GET
  @Operation(
      summary = "List the producers the caller sees",
      description =
          "Public producers, the caller's own, and private producers they are allowed on, by"
              + " name, each with its owner's name and whether the caller is subscribed. Never"
              + " keys, allow-lists or activity.")
  @APIResponse(
      responseCode = "200",
      description = "The producers, in items.",
      content = @Content(schema = @Schema(implementation = VisibleProducer.Items.class)))
  public VisibleProducer.Items list() {
    return producers.visibleTo(caller.get().userId());
  }

  @PUT
  @Path("/{id}/subscription")
  @Operation(
      summary = "Subscribe to a producer",
      description =
          "The caller's user, on all their devices, receives the producer's events from now on,"
              + " and finds its stored ones in their inbox. Subscribing to a producer already"
              + " subscribed to changes nothing. The request has no body.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, now subscribed.",
      content = @Content(schema = @Schema(implementation = VisibleProducer.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not see it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public VisibleProducer subscribe(@PathParam("id") UUID id) {
    return producers.subscribeTo(caller.get().userId(), id).orElseThrow(this::notFound);
  }

  @DELETE
  @Path("/{id}/subscription")
  @Operation(
      summary = "Unsubscribe from a producer",
      description =
          "The caller's user stops receiving the producer's events, and no longer finds them in"
              + " their inbox. Unsubscribing from a producer not subscribed to changes nothing.")
  @APIResponse(
      responseCode = "200",
      description = "The producer, now not subscribed.",
      content = @Content(schema = @Schema(implementation = VisibleProducer.class)))
  @APIResponse(
      responseCode = "404",
      description = "No producer has this ID, or the caller's user does not see it.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public VisibleProducer unsubscribe(@PathParam("id") UUID id) {
    return producers.unsubscribeFrom(caller.get().userId(), id).orElseThrow(this::notFound);
  }

  private NotFoundException notFound() {
    return new NotFoundException(
        Response.status(Response.Status.NOT_FOUND)
            .entity(new ApiError("Not found", 404, List.of()))
            .build());
  }
}
