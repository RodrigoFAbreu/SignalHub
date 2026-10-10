package io.github.rodrigofabreu.signalhub.event;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** How a user stands to a producer's events, for the operator's per-user listing. */
@Schema(
    name = "UserRelation",
    description =
        "OWNED: the user owns the producer that published the event. SUBSCRIBED: the user is"
            + " subscribed to that producer, so receives its events.")
public enum UserRelation {
  OWNED,
  SUBSCRIBED
}
