package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.api.ApiError;
import jakarta.ws.rs.ClientErrorException;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;
import java.util.List;

/**
 * A producer sent an idempotency key it already used for a different event: {@code 422}, since
 * storing the event would break the key's promise and returning the other one would hide the
 * mistake.
 */
class IdempotencyKeyReusedException extends ClientErrorException {

  private static final long serialVersionUID = 1L;

  static final int STATUS = 422;

  IdempotencyKeyReusedException() {
    super(
        Response.status(STATUS)
            .type(MediaType.APPLICATION_JSON_TYPE)
            .entity(
                new ApiError(
                    "Idempotency key already used",
                    STATUS,
                    List.of(
                        new ApiError.Violation(
                            EventResource.IDEMPOTENCY_KEY,
                            "was already used for a different event"))))
            .build());
  }
}
