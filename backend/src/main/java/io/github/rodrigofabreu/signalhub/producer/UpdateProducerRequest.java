package io.github.rodrigofabreu.signalhub.producer;

import static java.util.Collections.unmodifiableList;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code PATCH /api/v1/admin/producers/{id}}: each field present is changed. */
@Schema(
    name = "UpdateProducerRequest",
    description =
        "What to change on a producer: who sees it, the users allowed on it, or both. A field that"
            + " is omitted or null stays as it is; at least one must be given.")
public record UpdateProducerRequest(
    @Schema(
            description =
                "PUBLIC: every user may see the producer and subscribe. PRIVATE: only its owner"
                    + " and the users on the allow-list. Making a producer private ends the"
                    + " subscriptions of the users who then no longer see it.")
        Visibility visibility,
    @Schema(
            description =
                "The IDs of the users allowed on the producer besides its owner, replacing the"
                    + " list. They must exist and not be revoked. Users taken off a private"
                    + " producer stop receiving it.")
        @Size(max = 1000)
        List<@NotNull UUID> allowedUserIds) {

  public UpdateProducerRequest {
    // Copied without List.copyOf, which throws on a null ID before validation can report it.
    allowedUserIds =
        allowedUserIds == null ? null : unmodifiableList(new ArrayList<>(allowedUserIds));
  }

  boolean changesNothing() {
    return visibility == null && allowedUserIds == null;
  }
}
