package io.github.rodrigofabreu.signalhub.producer;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.UuidGenerator;

/** Persistence mapping of the {@code producers} table. Never exposed through the HTTP API. */
@Entity
@Table(name = "producers")
class ProducerEntity {

  @Id
  @UuidGenerator(style = UuidGenerator.Style.VERSION_7)
  private UUID id;

  @Column(nullable = false, updatable = false)
  private String name;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "disabled_at")
  private Instant disabledAt;

  protected ProducerEntity() {}

  ProducerEntity(String name, Instant createdAt) {
    this.name = name;
    this.createdAt = createdAt;
  }

  UUID id() {
    return id;
  }

  String name() {
    return name;
  }

  Instant createdAt() {
    return createdAt;
  }

  Instant disabledAt() {
    return disabledAt;
  }

  boolean enabled() {
    return disabledAt == null;
  }

  /** Keeps the original time if already disabled, so repeating the request changes nothing. */
  void disable(Instant now) {
    if (disabledAt == null) {
      disabledAt = now;
    }
  }

  void enable() {
    disabledAt = null;
  }
}
