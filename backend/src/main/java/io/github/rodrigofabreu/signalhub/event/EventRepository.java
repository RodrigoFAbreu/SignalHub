package io.github.rodrigofabreu.signalhub.event;

import io.quarkus.hibernate.orm.panache.PanacheRepositoryBase;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.UUID;

@ApplicationScoped
class EventRepository implements PanacheRepositoryBase<EventEntity, UUID> {

  /** The listing order. {@code id} makes it total, since events can share a {@code createdAt}. */
  static final Sort NEWEST_FIRST = Sort.descending("createdAt", "id");

  /**
   * Up to {@code count} events matching the query, in {@link #NEWEST_FIRST} order, starting after
   * the query's cursor. Served by the {@code (created_at, id)} indexes of V3, so a page costs the
   * same however deep it is.
   */
  List<EventEntity> find(EventQuery query, int count) {
    var conditions = new ArrayList<String>();
    var parameters = new HashMap<String, Object>();
    if (!query.producerIds().isEmpty()) {
      conditions.add("producerId in :producerIds");
      parameters.put("producerIds", query.producerIds());
    }
    if (!query.categories().isEmpty()) {
      conditions.add("category in :categories");
      parameters.put("categories", query.categories());
    }
    if (!query.severities().isEmpty()) {
      conditions.add("severity in :severities");
      parameters.put("severities", query.severities());
    }
    query
        .createdFrom()
        .ifPresent(
            from -> {
              conditions.add("createdAt >= :createdFrom");
              parameters.put("createdFrom", from);
            });
    query
        .createdBefore()
        .ifPresent(
            before -> {
              conditions.add("createdAt < :createdBefore");
              parameters.put("createdBefore", before);
            });
    query
        .after()
        .ifPresent(
            cursor -> {
              // A row comparison, which PostgreSQL answers with one index range scan.
              conditions.add("(createdAt, id) < (:afterCreatedAt, :afterId)");
              parameters.put("afterCreatedAt", cursor.createdAt());
              parameters.put("afterId", cursor.id());
            });
    var matching =
        conditions.isEmpty()
            ? findAll(NEWEST_FIRST)
            : find(String.join(" and ", conditions), NEWEST_FIRST, parameters);
    return matching.range(0, count - 1).list();
  }
}
