package io.github.rodrigofabreu.signalhub.event;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import java.time.Instant;
import java.util.Collection;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * A user's read state: which events they have read, on any of their devices, and never anyone
 * else's. An event is read for a user once a row says so; the operator's own read state is {@code
 * events.read_at}, kept by {@link EventRepository}. Callers check first that the user receives the
 * event; every statement here also limits itself to the user's subscriptions.
 */
@ApplicationScoped
class EventReads {

  private static final String SUBSCRIBED =
      "e.producer_id IN (SELECT producer_id FROM subscriptions WHERE user_id = :user)";

  private final EntityManager entityManager;

  EventReads(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /** Marks the event read for the user unless it already is, keeping the first read time. */
  void markRead(UUID userId, UUID eventId, Instant now) {
    entityManager
        .createNativeQuery(
            "INSERT INTO event_reads (user_id, event_id, read_at) VALUES (:user, :event, :now)"
                + " ON CONFLICT DO NOTHING")
        .setParameter("user", userId)
        .setParameter("event", eventId)
        .setParameter("now", now)
        .executeUpdate();
  }

  void markUnread(UUID userId, UUID eventId) {
    entityManager
        .createNativeQuery("DELETE FROM event_reads WHERE user_id = :user AND event_id = :event")
        .setParameter("user", userId)
        .setParameter("event", eventId)
        .executeUpdate();
  }

  /**
   * Marks read every unread event of the user's subscriptions at or before the given position in
   * listing order, so newer events stay unread; returns how many were marked.
   */
  int markReadThrough(UUID userId, Instant createdAt, UUID eventId, Instant now) {
    return entityManager
        .createNativeQuery(
            "INSERT INTO event_reads (user_id, event_id, read_at)"
                + " SELECT :user, e.id, :now FROM events e WHERE "
                + SUBSCRIBED
                + " AND (e.created_at, e.id) <= (:createdAt, :eventId)"
                + " AND NOT EXISTS (SELECT 1 FROM event_reads r"
                + " WHERE r.user_id = :user AND r.event_id = e.id)"
                + " ON CONFLICT DO NOTHING")
        .setParameter("user", userId)
        .setParameter("now", now)
        .setParameter("createdAt", createdAt)
        .setParameter("eventId", eventId)
        .executeUpdate();
  }

  /** How many events of the user's subscriptions they have not read. */
  long countUnread(UUID userId) {
    return ((Number)
            entityManager
                .createNativeQuery(
                    "SELECT count(*) FROM events e WHERE "
                        + SUBSCRIBED
                        + " AND NOT EXISTS (SELECT 1 FROM event_reads r"
                        + " WHERE r.user_id = :user AND r.event_id = e.id)")
                .setParameter("user", userId)
                .getSingleResult())
        .longValue();
  }

  /** When the user read each of these events; events they have not read are absent. */
  Map<UUID, Instant> readAt(UUID userId, Collection<UUID> eventIds) {
    var read = new HashMap<UUID, Instant>();
    if (eventIds.isEmpty()) {
      return read;
    }
    entityManager
        .createQuery(
            "select r.id.eventId, r.readAt from EventReadEntity r"
                + " where r.id.userId = :user and r.id.eventId in :events",
            Object[].class)
        .setParameter("user", userId)
        .setParameter("events", eventIds)
        .getResultList()
        .forEach(row -> read.put((UUID) row[0], (Instant) row[1]));
    return read;
  }
}
