package io.github.rodrigofabreu.signalhub.event;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * Each event's delivery records: how each push of it to each client went. Rows go with their event
 * and their client (foreign keys), so retention and deletes need nothing here.
 */
@ApplicationScoped
class EventDeliveries {

  // A provider's reason is a short code; this bounds what a misbehaving one could make us store.
  static final int MAX_DETAIL = 200;

  private final EntityManager entityManager;

  EventDeliveries(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /**
   * Records one push of the event to the client. Nothing is recorded if either was deleted since,
   * so a delete never fails because a push was in flight.
   */
  @Transactional
  void record(UUID eventId, UUID clientId, int attempt, DeliveryOutcome outcome, String detail) {
    entityManager
        .createNativeQuery(
            """
            INSERT INTO event_deliveries (event_id, client_id, attempt, outcome, detail, at)
            SELECT e.id, c.id, :attempt, :outcome, :detail, clock_timestamp()
            FROM events e, clients c WHERE e.id = :eventId AND c.id = :clientId
            """)
        .setParameter("eventId", eventId)
        .setParameter("clientId", clientId)
        .setParameter("attempt", attempt)
        .setParameter("outcome", outcome.name())
        .setParameter("detail", bounded(detail))
        .executeUpdate();
  }

  /** The event's records, oldest first; empty if no event has this ID. */
  @Transactional
  Optional<List<EventDelivery>> of(UUID eventId) {
    if (entityManager.find(EventEntity.class, eventId) == null) {
      return Optional.empty();
    }
    List<?> rows =
        entityManager
            .createNativeQuery(
                """
                SELECT d.client_id, c.name, d.attempt, d.outcome, d.detail, d.at
                FROM event_deliveries d JOIN clients c ON c.id = d.client_id
                WHERE d.event_id = :eventId
                ORDER BY d.at, d.id
                """)
            .setParameter("eventId", eventId)
            .getResultList();
    return Optional.of(
        rows.stream().map(Object[].class::cast).map(EventDeliveries::toDelivery).toList());
  }

  private static EventDelivery toDelivery(Object[] row) {
    return new EventDelivery(
        (UUID) row[0],
        (String) row[1],
        ((Number) row[2]).intValue(),
        DeliveryOutcome.valueOf((String) row[3]),
        (String) row[4],
        instant(row[5]));
  }

  private static Instant instant(Object value) {
    return value instanceof OffsetDateTime time ? time.toInstant() : (Instant) value;
  }

  private static String bounded(String detail) {
    if (detail == null || detail.isBlank()) {
      return null;
    }
    return detail.length() <= MAX_DETAIL ? detail : detail.substring(0, MAX_DETAIL);
  }
}
