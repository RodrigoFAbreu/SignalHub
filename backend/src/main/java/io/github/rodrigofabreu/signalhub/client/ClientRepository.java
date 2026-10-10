package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.push.DeliveryResult;
import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
class ClientRepository implements PanacheRepositoryBase<ClientEntity, UUID> {

  /**
   * Loads the client for a change, holding its row lock until the transaction ends. Concurrent
   * changes (a revocation and a push-target update) then apply one after the other instead of one
   * overwriting the other.
   */
  Optional<ClientEntity> findForUpdate(UUID id) {
    return findByIdOptional(id, LockModeType.PESSIMISTIC_WRITE);
  }

  /**
   * Removes this push target from every other client. A push address belongs to one installation,
   * so when an app is re-registered (for example after reinstalling) the new client takes it over
   * and the old one no longer receives duplicate pushes.
   */
  void releasePushTarget(String provider, String token, UUID keptBy) {
    update(
        "pushProvider = null, pushToken = null, pushUpdatedAt = null"
            + " where pushProvider = ?1 and pushToken = ?2 and id <> ?3",
        provider,
        token,
        keptBy);
  }

  /** How many of the user's clients are not revoked. */
  long countActive(UUID userId) {
    return count("userId = ?1 and revokedAt is null", userId);
  }

  /** Revokes every client of the user, dropping their push targets. */
  void revokeAllOf(UUID userId, Instant now) {
    update(
        "revokedAt = coalesce(revokedAt, ?1), pushProvider = null, pushToken = null,"
            + " pushUpdatedAt = null where userId = ?2",
        now,
        userId);
  }

  /**
   * Records that the client was active, unless a time at least as recent is already there, so
   * concurrent requests write once.
   */
  void recordActivity(UUID id, Instant at, Instant notAfter) {
    getEntityManager()
        .createNativeQuery(
            "UPDATE clients SET last_active_at = :at"
                + " WHERE id = :id AND (last_active_at IS NULL OR last_active_at <= :notAfter)")
        .setParameter("at", at)
        .setParameter("id", id)
        .setParameter("notAfter", notAfter)
        .executeUpdate();
  }

  /** Overwrites the client's last successful push. */
  void recordPushSuccess(UUID id, UUID eventId, Instant at) {
    getEntityManager()
        .createNativeQuery(
            "UPDATE clients SET last_push_succeeded_at = :at, last_push_succeeded_event_id = :eventId"
                + " WHERE id = :id")
        .setParameter("at", at)
        .setParameter("eventId", eventId)
        .setParameter("id", id)
        .executeUpdate();
  }

  /** Overwrites the client's last failed push. */
  void recordPushFailure(UUID id, UUID eventId, DeliveryResult result, Instant at) {
    getEntityManager()
        .createNativeQuery(
            """
            UPDATE clients
            SET last_push_failed_at = :at,
                last_push_failed_event_id = :eventId,
                last_push_failed_result = :result
            WHERE id = :id
            """)
        .setParameter("at", at)
        .setParameter("eventId", eventId)
        .setParameter("result", result.name())
        .setParameter("id", id)
        .executeUpdate();
  }

  /**
   * Pushes to the client waiting to be sent again. Counted from the retries themselves rather than
   * kept as a counter, so it cannot drift from them.
   */
  long pendingRetries(UUID id) {
    return ((Number)
            getEntityManager()
                .createNativeQuery("SELECT count(*) FROM push_retries WHERE client_id = :id")
                .setParameter("id", id)
                .getSingleResult())
        .longValue();
  }

  /** {@link #pendingRetries(UUID)} of every client that has any. */
  Map<UUID, Long> pendingRetries() {
    List<?> rows =
        getEntityManager()
            .createNativeQuery("SELECT client_id, count(*) FROM push_retries GROUP BY client_id")
            .getResultList();
    var counts = new HashMap<UUID, Long>();
    for (var row : rows) {
      var columns = (Object[]) row;
      counts.put((UUID) columns[0], ((Number) columns[1]).longValue());
    }
    return counts;
  }
}
