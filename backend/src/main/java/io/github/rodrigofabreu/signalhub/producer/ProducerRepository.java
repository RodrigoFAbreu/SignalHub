package io.github.rodrigofabreu.signalhub.producer;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.UUID;

@ApplicationScoped
class ProducerRepository implements PanacheRepositoryBase<ProducerEntity, UUID> {

  boolean nameExists(String name) {
    return count("name", name) > 0;
  }
}
