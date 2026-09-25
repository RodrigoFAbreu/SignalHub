package io.github.rodrigofabreu.signalhub.api;

import static java.util.stream.Collectors.joining;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.exc.MismatchedInputException;
import com.fasterxml.jackson.databind.exc.UnrecognizedPropertyException;
import com.fasterxml.jackson.databind.node.ObjectNode;
import jakarta.validation.ConstraintViolationException;
import jakarta.validation.ElementKind;
import jakarta.validation.Path;
import jakarta.ws.rs.WebApplicationException;
import jakarta.ws.rs.core.Response;
import java.time.temporal.Temporal;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;
import java.util.stream.StreamSupport;
import org.jboss.resteasy.reactive.server.ServerExceptionMapper;

/**
 * Turns request validation and JSON binding failures into {@link ApiError} bodies that name fields
 * by their JSON path, never by Java method or class names.
 */
class ApiExceptionMappers {

  @ServerExceptionMapper
  Response invalidRequest(ConstraintViolationException e) {
    var violations =
        e.getConstraintViolations().stream()
            .map(v -> new ApiError.Violation(jsonPath(v.getPropertyPath()), v.getMessage()))
            .sorted(
                Comparator.comparing(ApiError.Violation::field)
                    .thenComparing(ApiError.Violation::message))
            .toList();
    return badRequest(violations);
  }

  @ServerExceptionMapper({JsonProcessingException.class, MismatchedInputException.class})
  Response unreadableBody(JsonProcessingException e) {
    if (e instanceof MismatchedInputException mismatch) {
      return badRequest(List.of(new ApiError.Violation(jsonPath(mismatch), problemWith(mismatch))));
    }
    return badRequest(
        List.of(new ApiError.Violation("", "body is not valid JSON: " + e.getOriginalMessage())));
  }

  /**
   * Quarkus wraps JSON syntax errors (and nesting or length limits) in a plain 400; give them the
   * same body as other invalid input. Every other exception keeps its own response.
   */
  @ServerExceptionMapper
  Response webApplicationException(WebApplicationException e) {
    if (e.getResponse().getStatus() == 400
        && e.getCause() instanceof JsonProcessingException json) {
      return unreadableBody(json);
    }
    return e.getResponse();
  }

  private static Response badRequest(List<ApiError.Violation> violations) {
    return Response.status(Response.Status.BAD_REQUEST)
        .entity(new ApiError("Invalid request", 400, violations))
        .build();
  }

  /** Bean Validation paths start with the resource method and parameter; keep the body part. */
  private static String jsonPath(Path path) {
    return StreamSupport.stream(path.spliterator(), false)
        .filter(node -> node.getKind() == ElementKind.PROPERTY)
        .map(Path.Node::getName)
        .collect(joining("."));
  }

  private static String jsonPath(JsonMappingException e) {
    return e.getPath().stream()
        .map(ref -> ref.getFieldName() != null ? ref.getFieldName() : "[" + ref.getIndex() + "]")
        .collect(joining("."));
  }

  private static String problemWith(MismatchedInputException e) {
    if (e instanceof UnrecognizedPropertyException) {
      return "is not a recognized field";
    }
    Class<?> target = e.getTargetType();
    if (target == null) {
      return "has an invalid value";
    }
    if (target.isEnum()) {
      return "must be one of " + Arrays.toString(target.getEnumConstants());
    }
    if (Temporal.class.isAssignableFrom(target)) {
      return "must be an ISO-8601 timestamp with a UTC offset, e.g. 2026-09-25T12:03:00Z";
    }
    if (ObjectNode.class.isAssignableFrom(target)) {
      return "must be a JSON object";
    }
    if (target == String.class) {
      return "must be a JSON string";
    }
    return "has an invalid value";
  }
}
