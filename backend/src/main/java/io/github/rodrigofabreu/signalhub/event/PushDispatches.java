package io.github.rodrigofabreu.signalhub.event;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.time.Duration;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The outbox of events whose push is still to be dispatched, and of pushes to single clients that
 * failed temporarily and are to be sent again. Rows are claimed for a lease rather than locked, so
 * pushes are sent outside any transaction, and a claim left behind by a stopped dispatcher expires
 * and the push is sent again.
 */
@ApplicationScoped
class PushDispatches {

  private final EntityManager entityManager;

  PushDispatches(EntityManager entityManager) {
    this.entityManager = entityManager;
  }

  /** Records that the event needs a push. Runs in the transaction that stores the event. */
  void add(EventEntity event) {
    entityManager.persist(new PushDispatchEntity(event.id(), event.createdAt()));
  }

  /** Claims the oldest unclaimed (or expired) row for {@code lease}; empty if there is none. */
  @Transactional
  Optional<UUID> claimNext(Duration lease) {
    List<?> claimed =
        entityManager
            .createNativeQuery(
                """
                UPDATE push_dispatches SET claimed_until = now() + make_interval(secs => :lease)
                WHERE event_id = (
                    SELECT event_id FROM push_dispatches
                    WHERE claimed_until IS NULL OR claimed_until < now()
                    ORDER BY created_at, event_id
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED)
                RETURNING event_id
                """,
                UUID.class)
            .setParameter("lease", (double) lease.toSeconds())
            .getResultList();
    return claimed.stream().findFirst().map(UUID.class::cast);
  }

  /**
   * Removes the event's row once its push has been dispatched and, in the same transaction, records
   * the clients whose send failed temporarily, to be sent again after {@code retryDelay}. A client
   * already recorded for the event (the event was dispatched again) keeps its row.
   */
  @Transactional
  void complete(UUID eventId, Collection<UUID> retryClientIds, Duration retryDelay) {
    for (var clientId : retryClientIds) {
      entityManager
          .createNativeQuery(
              """
              INSERT INTO push_retries (event_id, client_id, attempts, next_attempt_at)
              VALUES (:eventId, :clientId, 1, now() + make_interval(secs => :delay))
              ON CONFLICT (event_id, client_id) DO NOTHING
              """)
          .setParameter("eventId", eventId)
          .setParameter("clientId", clientId)
          .setParameter("delay", (double) retryDelay.toSeconds())
          .executeUpdate();
    }
    entityManager
        .createNativeQuery("DELETE FROM push_dispatches WHERE event_id = :eventId")
        .setParameter("eventId", eventId)
        .executeUpdate();
  }

  /** Claims the retry due longest for {@code lease}; empty if none is due. */
  @Transactional
  Optional<PushRetry> claimNextRetry(Duration lease) {
    List<?> claimed =
        entityManager
            .createNativeQuery(
                """
                UPDATE push_retries SET claimed_until = now() + make_interval(secs => :lease)
                WHERE (event_id, client_id) = (
                    SELECT event_id, client_id FROM push_retries
                    WHERE next_attempt_at <= now()
                        AND (claimed_until IS NULL OR claimed_until < now())
                    ORDER BY next_attempt_at, event_id, client_id
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED)
                RETURNING event_id, client_id, attempts
                """)
            .setParameter("lease", (double) lease.toSeconds())
            .getResultList();
    return claimed.stream()
        .findFirst()
        .map(Object[].class::cast)
        .map(row -> new PushRetry((UUID) row[0], (UUID) row[1], ((Number) row[2]).intValue()));
  }

  /** Counts the send just made and releases the retry, to be sent again after {@code delay}. */
  @Transactional
  void retryLater(PushRetry retry, Duration delay) {
    entityManager
        .createNativeQuery(
            """
            UPDATE push_retries
            SET attempts = attempts + 1,
                next_attempt_at = now() + make_interval(secs => :delay),
                claimed_until = NULL
            WHERE event_id = :eventId AND client_id = :clientId
            """)
        .setParameter("delay", (double) delay.toSeconds())
        .setParameter("eventId", retry.eventId())
        .setParameter("clientId", retry.clientId())
        .executeUpdate();
  }

  /** Removes the retry: the push was delivered, failed for good, or ran out of attempts. */
  @Transactional
  void completeRetry(PushRetry retry) {
    entityManager
        .createNativeQuery(
            "DELETE FROM push_retries WHERE event_id = :eventId AND client_id = :clientId")
        .setParameter("eventId", retry.eventId())
        .setParameter("clientId", retry.clientId())
        .executeUpdate();
  }
}
