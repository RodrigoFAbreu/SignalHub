package io.github.rodrigofabreu.signalhub.event;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * What an event means for the owner, independent of the producer. Kept deliberately small: finer
 * distinctions belong in producer metadata. Values are part of the public contract and mirrored by
 * a check constraint in the database.
 */
@Schema(
    description =
        "What the event means for the owner. ACTION_REQUIRED: the owner must act (approve, answer,"
            + " decide). BLOCKED: work cannot continue until something external changes."
            + " COMPLETED: work finished. INFO: informational, no action expected.")
public enum Category {
  ACTION_REQUIRED,
  BLOCKED,
  COMPLETED,
  INFO
}
