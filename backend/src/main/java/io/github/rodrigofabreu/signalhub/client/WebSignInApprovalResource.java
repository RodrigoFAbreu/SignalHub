package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import io.github.rodrigofabreu.signalhub.producer.BearerToken;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.NotAuthorizedException;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.PathParam;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.Operation;
import org.eclipse.microprofile.openapi.annotations.media.Content;
import org.eclipse.microprofile.openapi.annotations.media.Schema;
import org.eclipse.microprofile.openapi.annotations.responses.APIResponse;
import org.eclipse.microprofile.openapi.annotations.security.SecurityRequirement;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

/**
 * A device signs a browser in: looks up the code the page shows (scanned or typed), then approves
 * or cancels it. Open to every role, a basic user included, for their own user; a browser cannot
 * approve another browser, only a device can.
 */
@Path("/api/v1/client/web-sign-ins")
@Tag(name = "Web sign-in")
@SecurityRequirement(name = ClientResource.SECURITY_SCHEME)
@APIResponse(
    responseCode = "401",
    description =
        "Missing, malformed, unknown or revoked client key. The response does not say which.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@APIResponse(
    responseCode = "403",
    description = "The caller is a signed-in browser, not a device.",
    content = @Content(schema = @Schema(implementation = ApiError.class)))
@ClientAuthenticated
@Produces(MediaType.APPLICATION_JSON)
public class WebSignInApprovalResource {

  public record LookupRequest(
      @Schema(
              required = true,
              description =
                  "The short code a person types (`K7Q-4MX`, any case, dash optional) or"
                      + " the scan code from the QR code or link.",
              examples = "K7Q-4MX")
          @NotBlank
          @Size(max = 64)
          String code) {}

  @Schema(name = "WebSignInRequest", description = "A browser waiting to be signed in.")
  public record Asked(
      @Schema(required = true, description = "The sign-in's ID, to approve or cancel it.") UUID id,
      @Schema(
              required = true,
              description = "How the server named the browser from its User-Agent.",
              examples = "Firefox on Linux")
          String browserName,
      @Schema(required = true, description = "When the page's codes stop working.")
          Instant expiresAt) {}

  private final WebSignInService signIns;
  private final AuthenticatedClient caller;

  WebSignInApprovalResource(WebSignInService signIns, AuthenticatedClient caller) {
    this.signIns = signIns;
    this.caller = caller;
  }

  @POST
  @Path("/lookup")
  @Consumes(MediaType.APPLICATION_JSON)
  @Operation(
      summary = "Look up a browser's sign-in code",
      description =
          "Finds the sign-in the code belongs to and makes this device the one that may approve or"
              + " cancel it, so the app can ask its user to sign that browser in. Wrong codes are"
              + " bounded: five per device and thirty in all in ten minutes, then 429 whatever"
              + " the code.")
  @APIResponse(
      responseCode = "200",
      description = "The browser waiting.",
      content = @Content(schema = @Schema(implementation = Asked.class)))
  @APIResponse(
      responseCode = "404",
      description = "No live sign-in has this code: wrong, expired or already used.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  @APIResponse(
      responseCode = "429",
      description = "Too many wrong codes lately.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public Asked lookup(@NotNull @Valid LookupRequest request) {
    refuseBrowsers();
    return switch (signIns.ask(caller.get().id(), request.code())) {
      case WebSignInService.Lookup.Found found ->
          new Asked(found.asked().id(), found.asked().browserName(), found.asked().expiresAt());
      case WebSignInService.Lookup.Unknown unknown ->
          throw error(Response.Status.NOT_FOUND, "Not found");
      case WebSignInService.Lookup.TooManyTries tooMany ->
          throw new ClientErrorException(
              Response.status(429)
                  .entity(new ApiError("Too many wrong codes", 429, List.of()))
                  .build());
    };
  }

  @POST
  @Path("/{id}/approve")
  @Operation(
      summary = "Sign the browser in",
      description =
          "The user approves the sign-in this device looked up. The page's next poll gets a"
              + " session for a new browser of this device's user, and the user's devices and the"
              + " admins' get a push saying so. The request has no body.")
  @APIResponse(responseCode = "204", description = "Approved.")
  @APIResponse(
      responseCode = "404",
      description = "Not a live sign-in this device looked up.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public void approve(@PathParam("id") UUID id) {
    refuseBrowsers();
    switch (signIns.approve(caller.get().id(), id)) {
      case DONE -> {}
      case UNKNOWN -> throw error(Response.Status.NOT_FOUND, "Not found");
      case REFUSED -> throw new NotAuthorizedException(BearerToken.unauthorized());
    }
  }

  @POST
  @Path("/{id}/cancel")
  @Operation(
      summary = "Decline a browser's sign-in",
      description = "The page is told the sign-in was cancelled. The request has no body.")
  @APIResponse(responseCode = "204", description = "Cancelled.")
  @APIResponse(
      responseCode = "404",
      description = "Not a live sign-in this device looked up.",
      content = @Content(schema = @Schema(implementation = ApiError.class)))
  public void cancel(@PathParam("id") UUID id) {
    refuseBrowsers();
    if (signIns.cancel(caller.get().id(), id) != WebSignInService.Outcome.DONE) {
      throw error(Response.Status.NOT_FOUND, "Not found");
    }
  }

  // A hijacked page must not be able to mint more sessions.
  private void refuseBrowsers() {
    if (caller.get().kind() == ClientKind.BROWSER) {
      throw error(Response.Status.FORBIDDEN, "Only a device can sign a browser in");
    }
  }

  private static WebApplicationException error(Response.Status status, String title) {
    return new ClientErrorException(
        Response.status(status)
            .entity(new ApiError(title, status.getStatusCode(), List.of()))
            .build());
  }
}
