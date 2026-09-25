package io.github.rodrigofabreu.signalhub.producer;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import java.util.UUID;

@ApplicationScoped
class ApiKeyRepository implements PanacheRepositoryBase<ApiKeyEntity, UUID> {

  List<ApiKeyEntity> ofProducer(UUID producerId) {
    return list("producer.id", Sort.by("createdAt").and("id"), producerId);
  }

  List<ApiKeyEntity> ofAllProducers() {
    return listAll(Sort.by("createdAt").and("id"));
  }
}
