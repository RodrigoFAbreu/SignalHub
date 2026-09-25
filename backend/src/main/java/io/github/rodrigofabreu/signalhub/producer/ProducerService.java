package io.github.rodrigofabreu.signalhub.producer;

import static java.util.stream.Collectors.groupingBy;

import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
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

  ProducerService(ProducerRepository producers, ApiKeyRepository keys) {
    this.producers = producers;
    this.keys = keys;
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

  /** Registers a producer with its first API key; empty if the name is taken. */
  @Transactional
  Optional<IssuedApiKey> create(String name) {
    if (producers.nameExists(name)) {
      return Optional.empty();
    }
    var producer = new ProducerEntity(name, now());
    producers.persist(producer);
    LOG.infof("Registered producer %s (%s)", producer.id(), name);
    return Optional.of(issueKey(producer));
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

  /** All producers by name. Two queries in total, whatever the number of producers. */
  @Transactional
  List<ProducerResponse> list() {
    var keysByProducer = keys.ofAllProducers().stream().collect(groupingBy(k -> k.producer().id()));
    return producers.listAll(Sort.by("name")).stream()
        .map(p -> toResponse(p, keysByProducer.getOrDefault(p.id(), List.of())))
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
    return toResponse(producer, keys.ofProducer(producer.id()));
  }

  private static ProducerResponse toResponse(ProducerEntity producer, List<ApiKeyEntity> keys) {
    return new ProducerResponse(
        producer.id(),
        producer.name(),
        producer.createdAt(),
        producer.disabledAt(),
        keys.stream()
            .map(k -> new ProducerResponse.ApiKey(k.id(), k.createdAt(), k.revokedAt()))
            .toList());
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
