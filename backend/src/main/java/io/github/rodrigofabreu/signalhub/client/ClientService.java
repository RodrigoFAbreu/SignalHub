package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.hibernate.id.uuid.UuidVersion7Strategy;
import org.jboss.logging.Logger;

/**
 * Registers and revokes clients, authenticates client keys, and records push targets. Logs only
 * client IDs and provider names, never keys, hashes or push tokens.
 */
@ApplicationScoped
public class ClientService {

  private static final Logger LOG = Logger.getLogger(ClientService.class);

  // Compared against when no client has the presented ID, so an unknown ID costs the same hash
  // comparison as a wrong secret.
  private static final byte[] NO_HASH = new byte[ApiKeys.HASH_BYTES];

  private final ClientRepository clients;

  ClientService(ClientRepository clients) {
    this.clients = clients;
  }

  /**
   * The client that owns this key, if the key is well formed, known and not revoked. Looks up
   * exactly one client by the ID embedded in the key.
   */
  @Transactional
  public Optional<ClientIdentity> authenticate(String clientKey) {
    var presentedHash = ApiKeys.hash(clientKey);
    var clientId = ClientKeys.clientIdOf(clientKey);
    if (clientId.isEmpty()) {
      LOG.debug("Rejected client credential: not a SignalHub client key");
      return Optional.empty();
    }
    var client = clients.findByIdOptional(clientId.get());
    var storedHash = client.map(ClientEntity::keyHash).orElse(NO_HASH);
    if (!ApiKeys.hashesMatch(presentedHash, storedHash) || client.isEmpty()) {
      LOG.debugf("Rejected client credential: unknown client or wrong secret (%s)", clientId.get());
      return Optional.empty();
    }
    if (client.get().revoked()) {
      LOG.debugf("Rejected client credential: client %s is revoked", clientId.get());
      return Optional.empty();
    }
    return Optional.of(new ClientIdentity(client.get().id(), client.get().name()));
  }

  /** Registers a client and issues its key, which is returned only here. */
  @Transactional
  IssuedClientKey create(String name) {
    // The ID is part of the key, so it is generated here rather than on persist; same UUIDv7
    // generator Hibernate uses for the other tables.
    var id = UuidVersion7Strategy.INSTANCE.generateUuid(null);
    var key = ClientKeys.generate(id);
    var client = new ClientEntity(id, name, ApiKeys.hash(key), now());
    clients.persist(client);
    LOG.infof("Registered client %s", id);
    return new IssuedClientKey(toResponse(client), key);
  }

  @Transactional
  Optional<ClientResponse> get(UUID id) {
    return clients.findByIdOptional(id).map(ClientService::toResponse);
  }

  /** All clients, oldest first. */
  @Transactional
  List<ClientResponse> list() {
    return clients.listAll(Sort.by("createdAt").and("id")).stream()
        .map(ClientService::toResponse)
        .toList();
  }

  /** Revokes the client permanently and drops its push target. Idempotent. */
  @Transactional
  Optional<ClientResponse> revoke(UUID id) {
    return clients
        .findForUpdate(id)
        .map(
            client -> {
              client.revoke(now());
              LOG.infof("Revoked client %s", id);
              return toResponse(client);
            });
  }

  /**
   * Sets the client's push target, replacing any previous one. The target is taken away from any
   * other client that had it, so one installation's address is never registered twice. Empty if the
   * client was revoked after it authenticated.
   */
  @Transactional
  Optional<ClientResponse> setPushTarget(UUID id, String provider, String token) {
    return active(id)
        .map(
            client -> {
              clients.releasePushTarget(provider, token, id);
              client.setPushTarget(provider, token, now());
              LOG.infof("Client %s set its push target (provider %s)", id, provider);
              return toResponse(client);
            });
  }

  /** Empty if the client was revoked after it authenticated. */
  @Transactional
  Optional<ClientResponse> clearPushTarget(UUID id) {
    return active(id)
        .map(
            client -> {
              client.clearPushTarget();
              LOG.infof("Client %s removed its push target", id);
              return toResponse(client);
            });
  }

  private Optional<ClientEntity> active(UUID id) {
    return clients.findForUpdate(id).filter(client -> !client.revoked());
  }

  @Transactional
  ClientResponse get(ClientIdentity client) {
    return toResponse(clients.findById(client.id()));
  }

  private static ClientResponse toResponse(ClientEntity client) {
    var pushTarget =
        client.pushProvider() == null
            ? null
            : new ClientResponse.PushTarget(client.pushProvider(), client.pushUpdatedAt());
    return new ClientResponse(
        client.id(), client.name(), client.createdAt(), client.revokedAt(), pushTarget);
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
