package io.github.rodrigofabreu.signalhub.producer;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
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

  @Column(nullable = false)
  private String name;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "disabled_at")
  private Instant disabledAt;

  // Whether the owner, not the operator, disabled it: only then may the owner enable it again.
  @Column(name = "disabled_by_owner", nullable = false)
  private boolean disabledByOwner;

  @Column(name = "owner_id", nullable = false, updatable = false)
  private UUID ownerId;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  private Visibility visibility;

  protected ProducerEntity() {}

  ProducerEntity(String name, UUID ownerId, Visibility visibility, Instant createdAt) {
    this.name = name;
    this.ownerId = ownerId;
    this.visibility = visibility;
    this.createdAt = createdAt;
  }

  UUID ownerId() {
    return ownerId;
  }

  Visibility visibility() {
    return visibility;
  }

  void setVisibility(Visibility visibility) {
    this.visibility = visibility;
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

  void rename(String name) {
    this.name = name;
  }

  /**
   * Disabled by the operator: keeps the original time if already disabled, so repeating the request
   * changes nothing, but the owner can no longer enable it, even if they had disabled it.
   */
  void disable(Instant now) {
    if (disabledAt == null) {
      disabledAt = now;
    }
    disabledByOwner = false;
  }

  /** Disabled by the owner; a producer already disabled stays as it was, whoever disabled it. */
  void disableByOwner(Instant now) {
    if (disabledAt == null) {
      disabledAt = now;
      disabledByOwner = true;
    }
  }

  boolean disabledByOperator() {
    return disabledAt != null && !disabledByOwner;
  }

  void enable() {
    disabledAt = null;
    disabledByOwner = false;
  }
}
