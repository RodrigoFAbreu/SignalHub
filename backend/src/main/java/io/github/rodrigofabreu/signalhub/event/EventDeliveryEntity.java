package io.github.rodrigofabreu.signalhub.event;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.UUID;

/**
 * Read-only mapping of the {@code event_deliveries} table, so the event listing can filter and
 * summarise by delivery records in a query. Rows are written by {@link EventDeliveries}.
 */
@Entity
@Table(name = "event_deliveries")
class EventDeliveryEntity {

  @Id
  @Column(name = "id", insertable = false, updatable = false)
  private Long id;

  @Column(name = "event_id", insertable = false, updatable = false)
  private UUID eventId;

  @Column(name = "client_id", insertable = false, updatable = false)
  private UUID clientId;

  @Column(name = "attempt", insertable = false, updatable = false)
  private int attempt;

  @Column(name = "outcome", insertable = false, updatable = false)
  private String outcome;

  protected EventDeliveryEntity() {}
}
