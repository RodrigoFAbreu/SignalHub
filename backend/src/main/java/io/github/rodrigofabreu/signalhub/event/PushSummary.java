package io.github.rodrigofabreu.signalhub.event;

import java.util.Collection;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * How an event's pushes went, in one word: the worst thing that happened to any of its devices'
 * pushes, judged by each device's latest delivery record (see {@link EventDelivery}). {@link
 * EventRepository} filters by the same rules in a query; the tests keep the two equal.
 */
@Schema(
    name = "PushSummary",
    description =
        "How the event's pushes went, by the worst thing that happened to any device, in this"
            + " order. GAVE_UP: a device's push failed temporarily on the last allowed attempt."
            + " FAILED: a device's push was refused, its target was rejected or its provider is"
            + " not configured. WAITING_FOR_RETRY: a device's push failed temporarily and a retry"
            + " is due. SENT: the provider accepted a push. NOT_SENT: every device was kept from"
            + " the push by its preferences or has no push target. PENDING: the push is not"
            + " dispatched yet. NOBODY_TO_REACH: it was dispatched and there was no device to"
            + " consider (events from before delivery records have none either). Later releases"
            + " may add values.")
public enum PushSummary {
  GAVE_UP,
  FAILED,
  WAITING_FOR_RETRY,
  SENT,
  NOT_SENT,
  PENDING,
  NOBODY_TO_REACH;

  /** The outcomes that are failures for good, whatever the attempt. */
  static final EnumSet<DeliveryOutcome> FAILURES =
      EnumSet.of(
          DeliveryOutcome.PERMANENT_FAILURE,
          DeliveryOutcome.INVALID_TARGET,
          DeliveryOutcome.UNSUPPORTED_PROVIDER);

  /** One delivery record, as far as the summary needs it. */
  record Record(UUID eventId, UUID clientId, int attempt, DeliveryOutcome outcome) {}

  /**
   * The summary of each of the events: from their delivery records, and whether the push of an
   * event waits in the outbox.
   */
  static Map<UUID, PushSummary> of(
      Collection<UUID> eventIds, List<Record> records, Collection<UUID> pending) {
    // Per event, each device's latest record: the one with the highest attempt.
    var latest = new HashMap<UUID, Map<UUID, Record>>();
    for (var record : records) {
      latest
          .computeIfAbsent(record.eventId(), id -> new HashMap<>())
          .merge(record.clientId(), record, (a, b) -> a.attempt() >= b.attempt() ? a : b);
    }
    var summaries = new HashMap<UUID, PushSummary>();
    for (var id : eventIds) {
      summaries.put(id, of(latest.getOrDefault(id, Map.of()).values(), pending.contains(id)));
    }
    return summaries;
  }

  private static PushSummary of(Collection<Record> latest, boolean pending) {
    if (latest.stream().anyMatch(r -> gaveUp(r))) {
      return GAVE_UP;
    }
    if (latest.stream().anyMatch(r -> FAILURES.contains(r.outcome()))) {
      return FAILED;
    }
    if (latest.stream().anyMatch(r -> r.outcome() == DeliveryOutcome.TRANSIENT_FAILURE)) {
      return WAITING_FOR_RETRY;
    }
    if (latest.stream().anyMatch(r -> r.outcome() == DeliveryOutcome.DELIVERED)) {
      return SENT;
    }
    if (!latest.isEmpty()) {
      return NOT_SENT;
    }
    return pending ? PENDING : NOBODY_TO_REACH;
  }

  private static boolean gaveUp(Record record) {
    return record.outcome() == DeliveryOutcome.TRANSIENT_FAILURE
        && record.attempt() >= EventPushDispatcher.MAX_ATTEMPTS;
  }
}
