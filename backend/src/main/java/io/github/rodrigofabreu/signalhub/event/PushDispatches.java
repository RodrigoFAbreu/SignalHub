package io.github.rodrigofabreu.signalhub.event;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * The outbox of events whose push is still to be dispatched. Rows are claimed for a lease rather
 * than locked, so pushes are sent outside any transaction, and a claim left behind by a stopped
 * dispatcher expires and the event is dispatched again.
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

  /** Removes the event's row once its push has been dispatched. */
  @Transactional
  void complete(UUID eventId) {
    entityManager
        .createNativeQuery("DELETE FROM push_dispatches WHERE event_id = :eventId")
        .setParameter("eventId", eventId)
        .executeUpdate();
  }
}
