package io.github.rodrigofabreu.signalhub.event;

/**
 * The listing's filter by {@link PushSummary}, as HQL conditions on an {@code EventEntity e}. They
 * follow {@link PushSummary#of}: the first summary in its order that holds, so each one excludes
 * the worse ones. Served by the {@code event_id} index of {@code event_deliveries}.
 */
final class PushPredicates {

  // A temporary failure on the last allowed attempt: final, so the device's latest record.
  private static final String GAVE_UP =
      records(
          "d.outcome = 'TRANSIENT_FAILURE' and d.attempt >= " + EventPushDispatcher.MAX_ATTEMPTS);

  private static final String FAILED =
      records("d.outcome in ('PERMANENT_FAILURE', 'INVALID_TARGET', 'UNSUPPORTED_PROVIDER')");

  // A temporary failure with attempts left, unless a later record of the device followed it.
  private static final String WAITING =
      records(
          "d.outcome = 'TRANSIENT_FAILURE' and d.attempt < "
              + EventPushDispatcher.MAX_ATTEMPTS
              + " and not exists (select 1"
              + " from EventDeliveryEntity n where n.eventId = d.eventId and n.clientId ="
              + " d.clientId and n.attempt > d.attempt)");

  private static final String SENT = records("d.outcome = 'DELIVERED'");

  private static final String ANY = records("1 = 1");

  private static final String PENDING =
      "exists (select 1 from PushDispatchEntity p where p.eventId = e.id)";

  private PushPredicates() {}

  static String of(PushSummary summary) {
    return switch (summary) {
      case GAVE_UP -> GAVE_UP;
      case FAILED -> all(FAILED, not(GAVE_UP));
      case WAITING_FOR_RETRY -> all(WAITING, not(GAVE_UP), not(FAILED));
      case SENT -> all(SENT, not(GAVE_UP), not(FAILED), not(WAITING));
      case NOT_SENT -> all(ANY, not(GAVE_UP), not(FAILED), not(WAITING), not(SENT));
      case PENDING -> all(not(ANY), PENDING);
      case NOBODY_TO_REACH -> all(not(ANY), not(PENDING));
    };
  }

  private static String records(String condition) {
    return "exists (select 1 from EventDeliveryEntity d where d.eventId = e.id and "
        + condition
        + ")";
  }

  private static String not(String condition) {
    return "not " + condition;
  }

  private static String all(String... conditions) {
    return "(" + String.join(" and ", conditions) + ")";
  }
}
