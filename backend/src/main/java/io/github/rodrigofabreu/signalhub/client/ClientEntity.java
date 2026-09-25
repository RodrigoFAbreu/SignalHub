package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.Arrays;
import java.util.UUID;

/**
 * Persistence mapping of the {@code clients} table: a client's key hash, never the key, and its
 * push target and push preferences. Never exposed through the HTTP API.
 */
@Entity
@Table(name = "clients")
class ClientEntity {

  // Assigned by the application, because the ID is part of the key that is hashed.
  @Id private UUID id;

  @Column(nullable = false, updatable = false)
  private String name;

  @Column(name = "key_hash", nullable = false, updatable = false)
  private byte[] keyHash;

  @Column(name = "created_at", nullable = false, updatable = false)
  private Instant createdAt;

  @Column(name = "revoked_at")
  private Instant revokedAt;

  @Column(name = "push_provider")
  private String pushProvider;

  @Column(name = "push_token")
  private String pushToken;

  @Column(name = "push_updated_at")
  private Instant pushUpdatedAt;

  @Column(name = "push_enabled", nullable = false)
  private boolean pushEnabled = true;

  @Column(name = "push_minimum_severity", nullable = false)
  private String pushMinimumSeverity = Severity.LOW.name();

  @Column(name = "push_muted_categories", nullable = false)
  private String[] pushMutedCategories = {};

  @Column(name = "push_muted_producers", nullable = false)
  private UUID[] pushMutedProducers = {};

  protected ClientEntity() {}

  ClientEntity(UUID id, String name, byte[] keyHash, Instant createdAt) {
    this.id = id;
    this.name = name;
    this.keyHash = keyHash.clone();
    this.createdAt = createdAt;
  }

  UUID id() {
    return id;
  }

  String name() {
    return name;
  }

  byte[] keyHash() {
    return keyHash.clone();
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

  String pushProvider() {
    return pushProvider;
  }

  String pushToken() {
    return pushToken;
  }

  Instant pushUpdatedAt() {
    return pushUpdatedAt;
  }

  /**
   * Keeps the original time if already revoked, so repeating the request changes nothing. A revoked
   * client must never receive pushes, so its push target goes too.
   */
  void revoke(Instant now) {
    if (revokedAt == null) {
      revokedAt = now;
    }
    clearPushTarget();
  }

  void setPushTarget(String provider, String token, Instant now) {
    pushProvider = provider;
    pushToken = token;
    pushUpdatedAt = now;
  }

  void clearPushTarget() {
    pushProvider = null;
    pushToken = null;
    pushUpdatedAt = null;
  }

  PushPreferences pushPreferences() {
    return new PushPreferences(
        pushEnabled,
        Severity.valueOf(pushMinimumSeverity),
        Arrays.stream(pushMutedCategories).map(Category::valueOf).toList(),
        Arrays.asList(pushMutedProducers));
  }

  void setPushPreferences(PushPreferences preferences) {
    pushEnabled = preferences.enabled();
    pushMinimumSeverity = preferences.minimumSeverity().name();
    pushMutedCategories =
        preferences.mutedCategories().stream().map(Category::name).toArray(String[]::new);
    pushMutedProducers = preferences.mutedProducerIds().toArray(UUID[]::new);
  }
}
