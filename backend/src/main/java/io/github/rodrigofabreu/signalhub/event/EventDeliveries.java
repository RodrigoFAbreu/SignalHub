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
                SELECT d.client_id, c.name, c.user_id, u.name, d.attempt, d.outcome, d.detail,
                       d.at
                FROM event_deliveries d JOIN clients c ON c.id = d.client_id
                JOIN users u ON u.id = c.user_id
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
        (UUID) row[2],
        (String) row[3],
        ((Number) row[4]).intValue(),
        DeliveryOutcome.valueOf((String) row[5]),
        (String) row[6],
        instant(row[7]));
  }

  /**
   * The users the event reached: those subscribed to its producer now, by name; empty if no event
   * has this ID. Users who joined or left since are not told apart.
   */
  @Transactional
  Optional<List<EventRecipient>> recipients(UUID eventId) {
    if (entityManager.find(EventEntity.class, eventId) == null) {
      return Optional.empty();
    }
    List<?> rows =
        entityManager
            .createNativeQuery(
                """
                SELECT u.id, u.name, u.id = p.owner_id
                FROM events e JOIN producers p ON p.id = e.producer_id
                JOIN subscriptions s ON s.producer_id = p.id
                JOIN users u ON u.id = s.user_id
                WHERE e.id = :eventId
                ORDER BY lower(u.name), u.id
                """)
            .setParameter("eventId", eventId)
            .getResultList();
    return Optional.of(
        rows.stream()
            .map(Object[].class::cast)
            .map(row -> new EventRecipient((UUID) row[0], (String) row[1], (Boolean) row[2]))
            .toList());
  }

  /** The user's newest delivery records across their devices, newest first. */
  @Transactional
  List<UserDelivery> recentFor(UUID userId, int limit) {
    List<?> rows =
        entityManager
            .createNativeQuery(
                """
                SELECT d.event_id, e.title, d.client_id, c.name, d.attempt, d.outcome, d.detail,
                       d.at
                FROM event_deliveries d JOIN clients c ON c.id = d.client_id
                JOIN events e ON e.id = d.event_id
                WHERE c.user_id = :userId
                ORDER BY d.at DESC, d.id DESC
                LIMIT :limit
                """)
            .setParameter("userId", userId)
            .setParameter("limit", limit)
            .getResultList();
    return rows.stream()
        .map(Object[].class::cast)
        .map(
            row ->
                new UserDelivery(
                    (UUID) row[0],
                    (String) row[1],
                    (UUID) row[2],
                    (String) row[3],
                    ((Number) row[4]).intValue(),
                    DeliveryOutcome.valueOf((String) row[5]),
                    (String) row[6],
                    instant(row[7])))
        .toList();
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
