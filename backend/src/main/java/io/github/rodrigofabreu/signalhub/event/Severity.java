package io.github.rodrigofabreu.signalhub.event;

import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * How urgently the owner should notice an event, in increasing order. Values are part of the public
 * contract and mirrored by a check constraint in the database.
 */
@Schema(
    description =
        "How urgently the owner should notice the event, from LOW to CRITICAL. LOW: can wait."
            + " NORMAL: the default for most events. HIGH: should be seen soon. CRITICAL: needs"
            + " immediate attention.")
public enum Severity {
  LOW,
  NORMAL,
  HIGH,
  CRITICAL
}
