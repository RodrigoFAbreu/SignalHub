package io.github.rodrigofabreu.signalhub.producer;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@ApplicationScoped
class ApiKeyRepository implements PanacheRepositoryBase<ApiKeyEntity, UUID> {

  /**
   * Records that the key was used, unless a time at least as recent is already there, so concurrent
   * requests write once.
   */
  void recordUse(UUID id, Instant at, Instant notAfter) {
    getEntityManager()
        .createNativeQuery(
            "UPDATE producer_api_keys SET last_used_at = :at"
                + " WHERE id = :id AND (last_used_at IS NULL OR last_used_at <= :notAfter)")
        .setParameter("at", at)
        .setParameter("id", id)
        .setParameter("notAfter", notAfter)
        .executeUpdate();
  }

  List<ApiKeyEntity> ofProducer(UUID producerId) {
    return list("producer.id", Sort.by("createdAt").and("id"), producerId);
  }

  List<ApiKeyEntity> ofOwner(UUID ownerId) {
    return list("producer.ownerId", Sort.by("createdAt").and("id"), ownerId);
  }

  List<ApiKeyEntity> ofAllProducers() {
    return listAll(Sort.by("createdAt").and("id"));
  }
}
