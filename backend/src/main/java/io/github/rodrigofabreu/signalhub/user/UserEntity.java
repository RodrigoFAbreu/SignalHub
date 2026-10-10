package io.github.rodrigofabreu.signalhub.user;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.UUID;
import org.hibernate.annotations.UuidGenerator;

/** Persistence mapping of the {@code users} table. Never exposed through the HTTP API. */
@Entity
@Table(name = "users")
class UserEntity {

  @Id
  @UuidGenerator(style = UuidGenerator.Style.VERSION_7)
  private UUID id;

  @Column(nullable = false)
  private String name;

  @Enumerated(EnumType.STRING)
  @Column(nullable = false)
  private Role role;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "revoked_at")
  private Instant revokedAt;

  protected UserEntity() {}

  UserEntity(String name, Role role, Instant createdAt) {
    this.name = name;
    this.role = role;
    this.createdAt = createdAt;
  }

  UUID id() {
    return id;
  }

  String name() {
    return name;
  }

  void rename(String name) {
    this.name = name;
  }

  Role role() {
    return role;
  }

  void setRole(Role role) {
    this.role = role;
  }

  Instant createdAt() {
    return createdAt;
  }

  Instant revokedAt() {
    return revokedAt;
  }

  boolean revoked() {
    return revokedAt != null;
  }

  /**
   * Keeps the original time if already revoked. A revoked user is never an admin, so the role drops
   * to basic.
   */
  void revoke(Instant now) {
    if (revokedAt == null) {
      revokedAt = now;
    }
    role = Role.BASIC;
  }

  UserRef ref() {
    return new UserRef(id, name, role);
  }
}
