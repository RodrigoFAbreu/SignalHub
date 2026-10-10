package io.github.rodrigofabreu.signalhub.producer;

import static java.util.stream.Collectors.groupingBy;
import static java.util.stream.Collectors.toMap;
import static java.util.stream.Collectors.toSet;

import io.github.rodrigofabreu.signalhub.LastUsed;
import io.github.rodrigofabreu.signalhub.user.NamedUser;
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
    var at = now();
    if (LastUsed.due(key.get().lastUsedAt(), at)) {
      keys.recordUse(keyId.get(), at, at.minus(LastUsed.INTERVAL));
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
        .findForUpdate(id)
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

  // ---- The producers a user owns, managed from their device. Every operation takes the caller's
  // user ID and finds only producers that user owns: another user's producer is not found, exactly
  // like one that does not exist. Logs only IDs.

  /** Registers a producer owned by the user with its first key, shown only in the result. */
  @Transactional
  OwnCreate createOwn(UUID ownerId, String name, Visibility visibility) {
    if (users.lockActive(ownerId).isEmpty()) {
      return new OwnCreate.OwnerRevoked();
    }
    return create(name, ownerId, visibility)
        .<OwnCreate>map(
            issued ->
                new OwnCreate.Created(
                    new IssuedOwnApiKey(
                        ownResponse(ownerId, issued.producer().id()),
                        issued.keyId(),
                        issued.apiKey())))
        .orElseGet(OwnCreate.NameTaken::new);
  }

  /** What {@link #createOwn} did. */
  sealed interface OwnCreate {
    record Created(IssuedOwnApiKey key) implements OwnCreate {}

    record NameTaken() implements OwnCreate {}

    record OwnerRevoked() implements OwnCreate {}
  }

  /** The user's producers by name, with their keys by prefix. Four queries in total. */
  @Transactional
  List<OwnProducerResponse> listOwn(UUID ownerId) {
    var owned = producers.ownedBy(ownerId);
    var keysByProducer = keys.ofOwner(ownerId).stream().collect(groupingBy(k -> k.producer().id()));
    var lastEvents = producers.lastEventTimes();
    var allowed = access.allowedByProducer();
    var subscribed = access.subscribedProducerIds(ownerId);
    var people = users.find(allowed.values().stream().flatMap(List::stream).collect(toSet()));
    return owned.stream()
        .map(
            p ->
                toOwnResponse(
                    p,
                    lastEvents.get(p.id()),
                    keysByProducer.getOrDefault(p.id(), List.of()),
                    people,
                    allowed.getOrDefault(p.id(), List.of()),
                    subscribed.contains(p.id())))
        .toList();
  }

  @Transactional
  Optional<OwnProducerResponse> getOwn(UUID ownerId, UUID id) {
    return ownedBy(ownerId, id, false).map(p -> ownResponse(ownerId, p.id()));
  }

  /**
   * Renames the producer and sets its visibility; a null leaves that as it is. A private producer's
   * users who no longer see it stop receiving it. Its keys and events are unchanged.
   */
  @Transactional
  Optional<OwnChange> updateOwn(UUID ownerId, UUID id, String name, Visibility visibility) {
    return ownedBy(ownerId, id, true)
        .map(
            producer -> {
              if (name != null && !name.equals(producer.name()) && producers.nameTaken(name, id)) {
                return new OwnChange.NameTaken();
              }
              if (name != null && !name.equals(producer.name())) {
                producer.rename(name);
                LOG.infof("Renamed producer %s", id);
              }
              if (visibility != null) {
                producer.setVisibility(visibility);
              }
              producers.flush();
              access.endSubscriptionsWithoutSight(id);
              LOG.infof("Producer %s is %s", id, producer.visibility());
              return updated(ownerId, id);
            });
  }

  @Transactional
  Optional<IssuedOwnApiKey> issueOwnKey(UUID ownerId, UUID id) {
    return ownedBy(ownerId, id, true)
        .map(
            producer -> {
              var issued = issueKey(producer);
              return new IssuedOwnApiKey(ownResponse(ownerId, id), issued.keyId(), issued.apiKey());
            });
  }

  /** Empty if the user owns no such producer, or it has no such key. Idempotent. */
  @Transactional
  Optional<OwnProducerResponse> revokeOwnKey(UUID ownerId, UUID id, UUID keyId) {
    return ownedBy(ownerId, id, true)
        .flatMap(
            producer ->
                keys.findByIdOptional(keyId)
                    .filter(key -> key.producer().id().equals(id))
                    .map(
                        key -> {
                          key.revoke(now());
                          LOG.infof("Revoked key %s of producer %s", keyId, id);
                          return ownResponse(ownerId, id);
                        }));
  }

  /** Disables the producer; one the operator disabled stays as it was. Idempotent. */
  @Transactional
  Optional<OwnChange> disableOwn(UUID ownerId, UUID id) {
    return ownedBy(ownerId, id, true)
        .map(
            producer -> {
              if (producer.enabled()) {
                producer.disableByOwner(now());
                LOG.infof("Owner disabled producer %s", id);
              }
              return updated(ownerId, id);
            });
  }

  /** Enables the producer, unless the operator disabled it. Idempotent. */
  @Transactional
  Optional<OwnChange> enableOwn(UUID ownerId, UUID id) {
    return ownedBy(ownerId, id, true)
        .map(
            producer -> {
              if (producer.disabledByOperator()) {
                return new OwnChange.DisabledByOperator();
              }
              if (!producer.enabled()) {
                producer.enable();
                LOG.infof("Owner enabled producer %s", id);
              }
              return updated(ownerId, id);
            });
  }

  /**
   * Puts a user who is not revoked on the producer's allow-list. The owner always sees the
   * producer, so naming them changes nothing. Idempotent.
   */
  @Transactional
  Optional<OwnChange> allowOwn(UUID ownerId, UUID id, UUID userId) {
    return ownedBy(ownerId, id, true)
        .map(
            producer -> {
              if (!users.isActive(userId)) {
                return new OwnChange.UnknownUser();
              }
              if (!userId.equals(ownerId) && access.allow(id, userId)) {
                LOG.infof("Allowed user %s on producer %s", userId, id);
              }
              return updated(ownerId, id);
            });
  }

  /** Takes the user off the allow-list; if the producer is private they stop receiving it. */
  @Transactional
  Optional<OwnChange> disallowOwn(UUID ownerId, UUID id, UUID userId) {
    return ownedBy(ownerId, id, true)
        .map(
            producer -> {
              if (access.disallow(id, userId)) {
                LOG.infof("Took user %s off the allow-list of producer %s", userId, id);
              }
              access.endSubscriptionsWithoutSight(id);
              return updated(ownerId, id);
            });
  }

  /** What a change to an own producer did, when the user owns it. */
  sealed interface OwnChange {
    record Updated(OwnProducerResponse producer) implements OwnChange {}

    record NameTaken() implements OwnChange {}

    /** The operator disabled the producer, so only the operator enables it. */
    record DisabledByOperator() implements OwnChange {}

    /** The user to allow does not exist or is revoked. */
    record UnknownUser() implements OwnChange {}
  }

  // ---- The producers a user sees, and their subscriptions.

  /** The producers the user sees, by name, with whether they receive each. */
  @Transactional
  VisibleProducer.Items visibleTo(UUID userId) {
    var visibleIds = access.visibleProducerIds(userId);
    var found =
        visibleIds.isEmpty()
            ? List.<ProducerEntity>of()
            : producers.list("id in ?1", Sort.by("name"), visibleIds);
    var subscribed = access.subscribedProducerIds(userId);
    var owners = users.find(found.stream().map(ProducerEntity::ownerId).collect(toSet()));
    return new VisibleProducer.Items(
        found.stream().map(p -> visible(p, owners, subscribed.contains(p.id()))).toList());
  }

  /**
   * Subscribes the user to a producer they see; empty, and nothing changes, if they do not see it
   * or it does not exist. Idempotent.
   */
  @Transactional
  Optional<VisibleProducer> subscribeTo(UUID userId, UUID producerId) {
    if (!access.subscribe(userId, producerId)) {
      return Optional.empty();
    }
    return visibleProducer(userId, producerId);
  }

  /** Ends the user's subscription to a producer they see; empty if they do not see it. */
  @Transactional
  Optional<VisibleProducer> unsubscribeFrom(UUID userId, UUID producerId) {
    if (!access.canSee(userId, producerId)) {
      return Optional.empty();
    }
    access.unsubscribe(userId, producerId);
    return visibleProducer(userId, producerId);
  }

  private Optional<VisibleProducer> visibleProducer(UUID userId, UUID producerId) {
    return producers
        .findByIdOptional(producerId)
        .map(
            p ->
                visible(
                    p,
                    users.find(java.util.Set.of(p.ownerId())),
                    access.isSubscribed(userId, producerId)));
  }

  private static VisibleProducer visible(
      ProducerEntity producer, Map<UUID, UserRef> owners, boolean subscribed) {
    return new VisibleProducer(
        producer.id(),
        producer.name(),
        NamedUser.of(owners.get(producer.ownerId())),
        producer.visibility(),
        !producer.enabled(),
        subscribed);
  }

  /** The producer, only if this user owns it; locked for update when the caller will change it. */
  private Optional<ProducerEntity> ownedBy(UUID ownerId, UUID id, boolean forUpdate) {
    return (forUpdate ? producers.findForUpdate(id) : producers.findByIdOptional(id))
        .filter(producer -> producer.ownerId().equals(ownerId));
  }

  private OwnChange updated(UUID ownerId, UUID id) {
    return new OwnChange.Updated(ownResponse(ownerId, id));
  }

  private OwnProducerResponse ownResponse(UUID ownerId, UUID id) {
    var producer = producers.findById(id);
    var allowed = access.allowed(id);
    return toOwnResponse(
        producer,
        producers.lastEventAt(id).orElse(null),
        keys.ofProducer(id),
        users.find(java.util.Set.copyOf(allowed)),
        allowed,
        access.isSubscribed(ownerId, id));
  }

  private static OwnProducerResponse toOwnResponse(
      ProducerEntity producer,
      Instant lastEventAt,
      List<ApiKeyEntity> keys,
      Map<UUID, UserRef> people,
      List<UUID> allowed,
      boolean subscribed) {
    return new OwnProducerResponse(
        producer.id(),
        producer.name(),
        producer.createdAt(),
        producer.disabledAt(),
        producer.disabledByOperator(),
        lastEventAt,
        keys.stream()
            .map(
                k ->
                    new OwnProducerResponse.Key(
                        k.id(),
                        ApiKeys.prefixOf(k.id()),
                        k.createdAt(),
                        k.lastUsedAt(),
                        k.revokedAt()))
            .toList(),
        producer.visibility(),
        allowed.stream()
            .map(people::get)
            .filter(java.util.Objects::nonNull)
            .sorted(java.util.Comparator.comparing(UserRef::name, String.CASE_INSENSITIVE_ORDER))
            .map(NamedUser::of)
            .toList(),
        subscribed);
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
            .map(
                k ->
                    new ProducerResponse.ApiKey(
                        k.id(), k.createdAt(), k.lastUsedAt(), k.revokedAt()))
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
