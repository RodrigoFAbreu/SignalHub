package io.github.rodrigofabreu.signalhub.producer;

import static java.util.stream.Collectors.groupingBy;
import static java.util.stream.Collectors.toMap;
import static java.util.stream.Collectors.toSet;

import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import io.github.rodrigofabreu.signalhub.user.UserRef;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.stream.Stream;
import org.jboss.logging.Logger;

/**
 * Registers producers, issues and revokes their API keys, and authenticates keys. Logs only key and
 * producer IDs, never keys or their hashes.
 */
@ApplicationScoped
public class ProducerService {

  private static final Logger LOG = Logger.getLogger(ProducerService.class);

  // Compared against when no stored key has the presented ID, so an unknown ID costs the same
  // hash comparison as a wrong secret.
  private static final byte[] NO_HASH = new byte[ApiKeys.HASH_BYTES];

  private final ProducerRepository producers;
  private final ApiKeyRepository keys;
  private final ProducerAccess access;
  private final UserDirectory users;

  ProducerService(
      ProducerRepository producers,
      ApiKeyRepository keys,
      ProducerAccess access,
      UserDirectory users) {
    this.producers = producers;
    this.keys = keys;
    this.access = access;
    this.users = users;
  }

  /**
   * The producer that owns this API key, if the key is well formed, known, not revoked, and its
   * producer is enabled. Looks up exactly one key record by the ID embedded in the key.
   */
  @Transactional
  public Optional<ProducerIdentity> authenticate(String apiKey) {
    var presentedHash = ApiKeys.hash(apiKey);
    var keyId = ApiKeys.keyIdOf(apiKey);
    if (keyId.isEmpty()) {
      LOG.debug("Rejected producer credential: not a SignalHub producer API key");
      return Optional.empty();
    }
    var key = keys.findByIdOptional(keyId.get());
    var storedHash = key.map(ApiKeyEntity::keyHash).orElse(NO_HASH);
    if (!ApiKeys.hashesMatch(presentedHash, storedHash) || key.isEmpty()) {
      LOG.debugf("Rejected producer credential: unknown key or wrong secret (key %s)", keyId.get());
      return Optional.empty();
    }
    var producer = key.get().producer();
    if (key.get().revoked()) {
      LOG.debugf("Rejected producer credential: key %s is revoked", keyId.get());
      return Optional.empty();
    }
    if (!producer.enabled()) {
      LOG.debugf("Rejected producer credential: producer %s is disabled", producer.id());
      return Optional.empty();
    }
    return Optional.of(new ProducerIdentity(producer.id(), producer.name()));
  }

  /** Any registered producer, enabled or not. */
  @Transactional
  public Optional<ProducerIdentity> find(UUID id) {
    return producers.findByIdOptional(id).map(p -> new ProducerIdentity(p.id(), p.name()));
  }

  /** Whether the producer exists and is not disabled. */
  @Transactional
  public boolean isEnabled(UUID id) {
    return producers.findByIdOptional(id).map(ProducerEntity::enabled).orElse(false);
  }

  /** The given producers by ID, enabled or not. One query whatever the number of IDs. */
  @Transactional
  public Map<UUID, ProducerIdentity> find(Collection<UUID> ids) {
    if (ids.isEmpty()) {
      return Map.of();
    }
    return producers.list("id in ?1", ids).stream()
        .collect(toMap(ProducerEntity::id, p -> new ProducerIdentity(p.id(), p.name())));
  }

  /**
   * Registers a producer owned by the user, with its first API key; empty if the name is taken. The
   * owner is subscribed to it from the start.
   */
  @Transactional
  Optional<IssuedApiKey> create(String name, UUID ownerId, Visibility visibility) {
    if (producers.nameExists(name)) {
      return Optional.empty();
    }
    var producer = new ProducerEntity(name, ownerId, visibility, now());
    producers.persist(producer);
    producers.flush();
    access.subscribeOwner(ownerId, producer.id());
    LOG.infof("Registered producer %s (%s) for user %s", producer.id(), name, ownerId);
    return Optional.of(issueKey(producer));
  }

  /**
   * Sets the producer's visibility and replaces its allow-list; a null leaves that as it is. Users
   * who no longer see a private producer stop receiving it. Empty if no producer has this ID.
   */
  @Transactional
  Optional<Update> update(UUID id, Visibility visibility, List<UUID> allowedUserIds) {
    return producers
        .findByIdOptional(id)
        .<Update>map(
            producer -> {
              if (allowedUserIds != null) {
                var unknown =
                    allowedUserIds.stream()
                        .filter(user -> !users.isActive(user))
                        .distinct()
                        .toList();
                if (!unknown.isEmpty()) {
                  return new Update.UnknownUsers(unknown);
                }
                access.setAllowed(
                    id,
                    allowedUserIds.stream().filter(u -> !u.equals(producer.ownerId())).toList());
              }
              if (visibility != null) {
                producer.setVisibility(visibility);
              }
              producers.flush();
              access.endSubscriptionsWithoutSight(id);
              LOG.infof("Updated producer %s: %s", id, producer.visibility());
              return new Update.Updated(toResponse(producer));
            });
  }

  /** What {@link #update} did to a producer that exists. */
  sealed interface Update {
    record Updated(ProducerResponse producer) implements Update {}

    /** The allow-list names users that do not exist or are revoked. */
    record UnknownUsers(List<UUID> ids) implements Update {
      public UnknownUsers {
        ids = List.copyOf(ids);
      }
    }
  }

  /** Disables every producer the user owns, so their keys stop working. */
  @Transactional
  public void disableAllOwnedBy(UUID ownerId) {
    for (var producer : producers.list("ownerId", ownerId)) {
      producer.disable(now());
      LOG.infof("Disabled producer %s of revoked user %s", producer.id(), ownerId);
    }
  }

  /** Issues an additional key. Existing keys stay valid until revoked, so rotation has no gap. */
  @Transactional
  Optional<IssuedApiKey> issueKey(UUID producerId) {
    return producers.findByIdOptional(producerId).map(this::issueKey);
  }

  @Transactional
  Optional<ProducerResponse> revokeKey(UUID producerId, UUID keyId) {
    return keys.findByIdOptional(keyId)
        .filter(key -> key.producer().id().equals(producerId))
        .map(
            key -> {
              key.revoke(now());
              LOG.infof("Revoked key %s of producer %s", keyId, producerId);
              return toResponse(key.producer());
            });
  }

  @Transactional
  Optional<ProducerResponse> disable(UUID id) {
    return producers
        .findByIdOptional(id)
        .map(
            producer -> {
              producer.disable(now());
              LOG.infof("Disabled producer %s", id);
              return toResponse(producer);
            });
  }

  @Transactional
  Optional<ProducerResponse> enable(UUID id) {
    return producers
        .findByIdOptional(id)
        .map(
            producer -> {
              producer.enable();
              LOG.infof("Enabled producer %s", id);
              return toResponse(producer);
            });
  }

  @Transactional
  Optional<ProducerResponse> get(UUID id) {
    return producers.findByIdOptional(id).map(this::toResponse);
  }

  /** All producers by name. Three queries in total, whatever the number of producers. */
  @Transactional
  List<ProducerResponse> list() {
    var keysByProducer = keys.ofAllProducers().stream().collect(groupingBy(k -> k.producer().id()));
    var lastEvents = producers.lastEventTimes();
    var all = producers.listAll(Sort.by("name"));
    var allowed = access.allowedByProducer();
    var people =
        users.find(
            Stream.concat(
                    all.stream().map(ProducerEntity::ownerId),
                    allowed.values().stream().flatMap(List::stream))
                .collect(toSet()));
    return all.stream()
        .map(
            p ->
                toResponse(
                    p,
                    lastEvents.get(p.id()),
                    keysByProducer.getOrDefault(p.id(), List.of()),
                    people,
                    allowed.getOrDefault(p.id(), List.of())))
        .toList();
  }

  private IssuedApiKey issueKey(ProducerEntity producer) {
    var keyId = UUID.randomUUID();
    var apiKey = ApiKeys.generate(keyId);
    keys.persist(new ApiKeyEntity(keyId, producer, ApiKeys.hash(apiKey), now()));
    LOG.infof("Issued key %s to producer %s", keyId, producer.id());
    return new IssuedApiKey(toResponse(producer), keyId, apiKey);
  }

  private ProducerResponse toResponse(ProducerEntity producer) {
    var allowed = access.allowed(producer.id());
    var people =
        users.find(Stream.concat(Stream.of(producer.ownerId()), allowed.stream()).collect(toSet()));
    return toResponse(
        producer,
        producers.lastEventAt(producer.id()).orElse(null),
        keys.ofProducer(producer.id()),
        people,
        allowed);
  }

  private static ProducerResponse toResponse(
      ProducerEntity producer,
      Instant lastEventAt,
      List<ApiKeyEntity> keys,
      Map<UUID, UserRef> people,
      List<UUID> allowed) {
    return new ProducerResponse(
        producer.id(),
        producer.name(),
        producer.createdAt(),
        producer.disabledAt(),
        lastEventAt,
        keys.stream()
            .map(k -> new ProducerResponse.ApiKey(k.id(), k.createdAt(), k.revokedAt()))
            .toList(),
        people.get(producer.ownerId()),
        producer.visibility(),
        allowed.stream()
            .map(people::get)
            .filter(java.util.Objects::nonNull)
            .sorted(java.util.Comparator.comparing(UserRef::name, String.CASE_INSENSITIVE_ORDER))
            .toList());
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
