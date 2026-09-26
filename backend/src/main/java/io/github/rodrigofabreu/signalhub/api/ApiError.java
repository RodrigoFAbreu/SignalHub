package io.github.rodrigofabreu.signalhub.api;

import jakarta.ws.rs.core.Response;
import java.util.List;
import java.util.Objects;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Error body of every error response from the product API. */
@Schema(name = "Error", description = "Why a request was rejected.")
public record ApiError(
    @Schema(required = true, examples = "Invalid request") String title,
    @Schema(required = true, examples = "400") int status,
    @Schema(required = true, description = "Per-field problems; empty when not field-specific.")
        List<Violation> violations) {

  public ApiError {
    violations = List.copyOf(violations);
  }

  /** An error with no per-field problems, titled by the status's reason phrase. */
  public static ApiError of(Response.StatusType status) {
    // A status JAX-RS does not name has no reason phrase, but the title is required.
    var title = Objects.requireNonNullElse(status.getReasonPhrase(), "Error");
    return new ApiError(title, status.getStatusCode(), List.of());
  }

  @Schema(name = "Violation")
  public record Violation(
      @Schema(
              required = true,
              description = "JSON path of the offending field, or empty for the whole body.",
              examples = "severity")
          String field,
      @Schema(required = true, examples = "must not be null") String message) {}
}
