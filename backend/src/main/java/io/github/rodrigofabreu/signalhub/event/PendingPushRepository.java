package io.github.rodrigofabreu.signalhub.event;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.List;
import java.util.UUID;

@ApplicationScoped
class PendingPushRepository implements PanacheRepositoryBase<PendingPushEntity, UUID> {

  /** Up to {@code count} queued events with what their push needs, oldest first. */
  List<PendingPush> oldest(int count) {
    return getEntityManager()
        .createQuery(
            "select new "
                + PendingPush.class.getName()
                + "(e.id, e.title, e.message)"
                + " from PendingPushEntity p, EventEntity e where e.id = p.eventId"
                + " order by p.queuedAt, p.eventId",
            PendingPush.class)
        .setMaxResults(count)
        .getResultList();
  }
}
