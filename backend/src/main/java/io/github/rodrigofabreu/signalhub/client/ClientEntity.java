package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.event.Category;
import io.github.rodrigofabreu.signalhub.event.Severity;
import io.github.rodrigofabreu.signalhub.push.DeliveryResult;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.time.Instant;
import java.util.Arrays;
import java.util.UUID;

/**
 * Persistence mapping of the {@code clients} table: a client's key hash, never the key, and its
 * name, the user it belongs to, and its push target and push preferences. Never exposed through the
 * HTTP API.
 */
@Entity
@Table(name = "clients")
class ClientEntity {

  // Assigned by the application, because the ID is part of the key that is hashed.
  @Id private UUID id;

  @Column(nullable = false)
  private String name;

  // The user the device belongs to. Fixed for the device's life.
  @Column(name = "user_id", nullable = false, updatable = false)
  private UUID userId;

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

  // Written only by ClientRepository's own statements after each push, so Hibernate's updates of a
  // client (a new push target, a revocation) never overwrite a result recorded meanwhile.
  @Column(name = "last_push_succeeded_at", insertable = false, updatable = false)
  private Instant lastPushSucceededAt;

  @Column(name = "last_push_succeeded_event_id", insertable = false, updatable = false)
  private UUID lastPushSucceededEventId;

  @Column(name = "last_push_failed_at", insertable = false, updatable = false)
  private Instant lastPushFailedAt;

  @Column(name = "last_push_failed_event_id", insertable = false, updatable = false)
  private UUID lastPushFailedEventId;

  @Column(name = "last_push_failed_result", insertable = false, updatable = false)
  private String lastPushFailedResult;

  // Written only by ClientRepository's own statement, at most once per LastUsed.INTERVAL, for the
  // same reason as the push results.
  @Column(name = "last_active_at", insertable = false, updatable = false)
  private Instant lastActiveAt;

  protected ClientEntity() {}

  ClientEntity(UUID id, String name, UUID userId, byte[] keyHash, Instant createdAt) {
    this.id = id;
    this.name = name;
    this.userId = userId;
    this.keyHash = keyHash.clone();
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

  UUID userId() {
    return userId;
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

  /** When the client last made an authenticated request, to within a minute; null if never. */
  Instant lastActiveAt() {
    return lastActiveAt;
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

  /** The last push the provider accepted; null if there has been none. */
  PushStatus.Success lastPushSuccess() {
    return lastPushSucceededAt == null
        ? null
        : new PushStatus.Success(lastPushSucceededAt, lastPushSucceededEventId);
  }

  /** The last push that failed; null if none has. */
  PushStatus.Failure lastPushFailure() {
    return lastPushFailedAt == null
        ? null
        : new PushStatus.Failure(
            lastPushFailedAt, lastPushFailedEventId, DeliveryResult.valueOf(lastPushFailedResult));
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
