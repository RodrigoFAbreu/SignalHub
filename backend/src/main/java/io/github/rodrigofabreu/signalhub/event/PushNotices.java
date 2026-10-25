package io.github.rodrigofabreu.signalhub.event;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.sql.SQLException;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The notices that a question was answered, closed or deleted, to be pushed to the devices that
 * were shown the event. A notice is written in the transaction of the change it announces, so it is
 * never lost, and waits while the event's own push is still to be dispatched, so that dispatch
 * cannot add a device after the notice. Rows are claimed for a lease, like {@link PushDispatches},
 * sent once and deleted.
 */
@ApplicationScoped
class PushNotices {

  static final String ANSWERED = "answered";
  static final String CLOSED = "closed";
  static final String DELETED = "deleted";

  /** A claimed notice and the devices it goes to. */
  record Notice(UUID id, UUID eventId, String notice, List<UUID> clientIds) {
    Notice {
      clientIds = List.copyOf(clientIds);
    }
  }

  private final EntityManager entityManager;

  PushNotices(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /** Records a notice to send at {@code dueAt}, to the event's devices except {@code skip}. */
  void add(UUID eventId, String notice, Instant dueAt, UUID skipClientId) {
    entityManager
        .createNativeQuery(
            """
            INSERT INTO push_notices (id, event_id, notice, due_at, skip_client_id)
            VALUES (gen_random_uuid(), :event, :notice, :due, :skip)
            """)
        .setParameter("event", eventId)
        .setParameter("notice", notice)
        .setParameter("due", dueAt)
        .setParameter("skip", skipClientId)
        .executeUpdate();
  }

  /** Drops the notice due at the question's closesAt: it ended before, and said so itself. */
  void cancelTimed(UUID eventId, Instant now) {
    entityManager
        .createNativeQuery(
            "DELETE FROM push_notices WHERE event_id = :event AND notice = 'closed'"
                + " AND due_at > :now")
        .setParameter("event", eventId)
        .setParameter("now", now)
        .executeUpdate();
  }

  /**
   * Records a {@code deleted} notice for each of these events that is an open question some device
   * was shown. Call it in the transaction that deletes them, before the delete: it reads the
   * delivery records that go with the events.
   */
  void recordDeleted(Collection<UUID> eventIds, Instant now) {
    if (eventIds.isEmpty()) {
      return;
    }
    entityManager
        .createNativeQuery(
            """
            INSERT INTO push_notices (id, event_id, notice, due_at, client_ids)
            SELECT gen_random_uuid(), e.id, 'deleted', :now,
                   ARRAY(SELECT DISTINCT d.client_id FROM event_deliveries d
                         WHERE d.event_id = e.id AND d.outcome = 'DELIVERED')
            FROM events e
            WHERE e.id IN :events AND e.ask IS NOT NULL
              AND (e.ask_closes_at IS NULL OR e.ask_closes_at > :now)
              AND NOT EXISTS (SELECT 1 FROM event_answers a WHERE a.event_id = e.id)
              AND EXISTS (SELECT 1 FROM event_deliveries d
                          WHERE d.event_id = e.id AND d.outcome = 'DELIVERED')
            """)
        .setParameter("events", eventIds)
        .setParameter("now", now)
        .executeUpdate();
  }

  /**
   * Claims the oldest due notice whose event has no push left to dispatch; empty if there is none.
   */
  @Transactional
  Optional<Notice> claimNext(Duration lease) {
    List<?> claimed =
        entityManager
            .createNativeQuery(
                """
                UPDATE push_notices SET claimed_until = now() + make_interval(secs => :lease)
                WHERE id = (
                    SELECT n.id FROM push_notices n
                    WHERE n.due_at <= now()
                      AND (n.claimed_until IS NULL OR n.claimed_until < now())
                      AND NOT EXISTS (SELECT 1 FROM push_dispatches d WHERE d.event_id = n.event_id)
                    ORDER BY n.due_at, n.id
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED)
                RETURNING id, event_id, notice, skip_client_id, client_ids
                """)
            .setParameter("lease", (double) lease.toSeconds())
            .getResultList();
    return claimed.stream().findFirst().map(Object[].class::cast).map(this::resolve);
  }

  /** The devices a claimed notice goes to; none for a notice that no longer applies. */
  private Notice resolve(Object[] row) {
    var id = (UUID) row[0];
    var eventId = (UUID) row[1];
    var notice = (String) row[2];
    var skip = (UUID) row[3];
    if (notice.equals(DELETED)) {
      return new Notice(id, eventId, notice, uuids(row[4]));
    }
    // A timed close is moot if the question was answered, or the event is gone.
    if (notice.equals(CLOSED) && answeredOrGone(eventId)) {
      return new Notice(id, eventId, notice, List.of());
    }
    List<?> clients =
        entityManager
            .createNativeQuery(
                """
                SELECT DISTINCT client_id FROM event_deliveries
                WHERE event_id = :event AND outcome = 'DELIVERED'
                  AND (CAST(:skip AS uuid) IS NULL OR client_id <> :skip)
                """)
            .setParameter("event", eventId)
            .setParameter("skip", skip)
            .getResultList();
    return new Notice(id, eventId, notice, clients.stream().map(UUID.class::cast).toList());
  }

  private boolean answeredOrGone(UUID eventId) {
    return entityManager
        .createNativeQuery(
            """
            SELECT 1 FROM events e WHERE e.id = :event
              AND NOT EXISTS (SELECT 1 FROM event_answers a
                              WHERE a.event_id = e.id AND a.kind = 'ANSWER')
            """)
        .setParameter("event", eventId)
        .getResultList()
        .isEmpty();
  }

  private static List<UUID> uuids(Object column) {
    try {
      if (column instanceof java.sql.Array array) {
        return List.of((UUID[]) array.getArray());
      }
      return column == null ? List.of() : List.of((UUID[]) column);
    } catch (SQLException e) {
      throw new IllegalStateException("A notice's devices could not be read", e);
    }
  }

  /** Removes the notice once it has been sent. */
  @Transactional
  void complete(UUID id) {
    entityManager
        .createNativeQuery("DELETE FROM push_notices WHERE id = :id")
        .setParameter("id", id)
        .executeUpdate();
  }

  @Transactional
  long backlog() {
    return ((Number)
            entityManager.createNativeQuery("SELECT count(*) FROM push_notices").getSingleResult())
        .longValue();
  }
}
