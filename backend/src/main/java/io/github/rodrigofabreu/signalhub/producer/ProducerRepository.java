package io.github.rodrigofabreu.signalhub.producer;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.LockModeType;
import java.time.Instant;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
class ProducerRepository implements PanacheRepositoryBase<ProducerEntity, UUID> {

  boolean nameExists(String name) {
    return count("name", name) > 0;
  }

  /** Whether another producer has this name. */
  boolean nameTaken(String name, UUID except) {
    return count("name = ?1 and id <> ?2", name, except) > 0;
  }

  /** Holds the producer's row lock until the transaction ends, so changes to it apply in turn. */
  Optional<ProducerEntity> findForUpdate(UUID id) {
    return findByIdOptional(id, LockModeType.PESSIMISTIC_WRITE);
  }

  List<ProducerEntity> ownedBy(UUID ownerId) {
    return list("ownerId", Sort.by("name"), ownerId);
  }

  /**
   * When the producer's most recent stored event was received. One lookup on the events index by
   * producer and time, however many events it has.
   */
  Optional<Instant> lastEventAt(UUID producerId) {
    return Optional.ofNullable(
        getEntityManager()
            .createQuery(
                "select max(e.createdAt) from EventEntity e where e.producerId = :id",
                Instant.class)
            .setParameter("id", producerId)
            .getSingleResult());
  }

  /**
   * {@link #lastEventAt} of every producer that has a stored event, in one query. A subquery per
   * producer rather than a grouping, so each is one index lookup instead of a scan of all events.
   */
  Map<UUID, Instant> lastEventTimes() {
    var times = new HashMap<UUID, Instant>();
    getEntityManager()
        .createQuery(
            "select p.id, (select max(e.createdAt) from EventEntity e where e.producerId = p.id)"
                + " from ProducerEntity p",
            Object[].class)
        .getResultStream()
        .filter(row -> row[1] != null)
        .forEach(row -> times.put((UUID) row[0], (Instant) row[1]));
    return times;
  }
}
