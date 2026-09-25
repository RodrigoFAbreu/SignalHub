package io.github.rodrigofabreu.signalhub.event;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.UUID;

@ApplicationScoped
class EventRepository implements PanacheRepositoryBase<EventEntity, UUID> {}
