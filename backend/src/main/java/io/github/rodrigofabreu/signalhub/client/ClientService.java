package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.github.rodrigofabreu.signalhub.push.DeliveryResult;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.function.Function;
import org.hibernate.id.uuid.UuidVersion7Strategy;
import org.jboss.logging.Logger;

/**
 * Registers and revokes clients, authenticates client keys, and records push targets and push
 * preferences. Logs only client IDs and provider names, never keys, hashes or push tokens.
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

  /**
   * Registers a client, an admin device or not, and issues its key, which is returned only here.
   */
  @Transactional
  IssuedClientKey create(String name, boolean admin) {
    // The ID is part of the key, so it is generated here rather than on persist; same UUIDv7
    // generator Hibernate uses for the other tables.
    var id = UuidVersion7Strategy.INSTANCE.generateUuid(null);
    var key = ClientKeys.generate(id);
    var client = new ClientEntity(id, name, admin, ApiKeys.hash(key), now());
    clients.persist(client);
    LOG.infof("Registered client %s%s", id, admin ? " as an admin device" : "");
    return new IssuedClientKey(toResponse(client), key);
  }

  /** The client and its latest push results. */
  @Transactional
  Optional<ManagedClientResponse> get(UUID id) {
    return clients
        .findByIdOptional(id)
        .map(client -> toManagedResponse(client, clients.pendingRetries(id)));
  }

  /** All clients, oldest first, and their latest push results. */
  @Transactional
  List<ManagedClientResponse> list() {
    var pendingRetries = clients.pendingRetries();
    return clients.listAll(Sort.by("createdAt").and("id")).stream()
        .map(client -> toManagedResponse(client, pendingRetries.getOrDefault(client.id(), 0L)))
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
   * Renames the client and grants or takes away its admin rights; a null leaves that field as it
   * is. Empty if no client has this ID. A revoked client never changes: it is not a device of the
   * owner's any more.
   */
  @Transactional
  Optional<Update> update(UUID id, String name, Boolean admin) {
    return clients
        .findForUpdate(id)
        .map(
            client -> {
              if (client.revoked()) {
                return new Update.Revoked();
              }
              if (name != null && !name.equals(client.name())) {
                client.rename(name);
                LOG.infof("Renamed client %s", id);
              }
              if (admin != null && admin != client.admin()) {
                client.setAdmin(admin);
                LOG.infof(
                    "Client %s %s", id, admin ? "is now an admin device" : "is no longer an admin");
              }
              return new Update.Updated(toManagedResponse(client, clients.pendingRetries(id)));
            });
  }

  /** What {@link #update} did to a client that exists. */
  sealed interface Update {
    record Updated(ManagedClientResponse client) implements Update {}

    record Revoked() implements Update {}
  }

  /**
   * Every client, as {@link #list()}, if the caller is an active admin device; otherwise why not.
   * Nothing changes, so the caller is not locked.
   */
  @Transactional
  DeviceList listFor(UUID callerId) {
    var caller = clients.findByIdOptional(callerId).orElseThrow();
    if (caller.revoked()) {
      return new DeviceList.Refused(Refusal.CALLER_REVOKED);
    }
    if (!caller.admin()) {
      return new DeviceList.Refused(Refusal.NOT_AN_ADMIN);
    }
    return new DeviceList.Listed(new ClientList(list()));
  }

  /**
   * An admin device makes another device an admin. Making an admin an admin changes nothing; a
   * revoked device cannot be made one.
   */
  @Transactional
  DeviceChange makeAdminBy(UUID callerId, UUID id) {
    return changeBy(
        callerId,
        id,
        client -> {
          if (client.revoked()) {
            return new DeviceChange.Refused(Refusal.CLIENT_REVOKED);
          }
          if (client.admin()) {
            return done(client, false);
          }
          client.setAdmin(true);
          LOG.infof("Client %s made client %s an admin device", callerId, id);
          return done(client, true);
        });
  }

  /**
   * An admin device revokes a device that is not an admin. Revoking a revoked device changes
   * nothing; an admin, the caller included, can be revoked only with the admin token.
   */
  @Transactional
  DeviceChange revokeBy(UUID callerId, UUID id) {
    return changeBy(
        callerId,
        id,
        client -> {
          if (client.revoked()) {
            return done(client, false);
          }
          if (client.admin()) {
            return new DeviceChange.Refused(Refusal.CLIENT_IS_ADMIN);
          }
          client.revoke(now());
          LOG.infof("Client %s revoked client %s", callerId, id);
          return done(client, true);
        });
  }

  /**
   * Checks that the caller is an active admin device before looking at the target, so a client that
   * is not one learns nothing about the others. Locks both rows, in a fixed order so two admin
   * devices acting on each other cannot deadlock, and holds the caller's lock so an operator
   * revoking it or taking its rights away meanwhile is applied before this change or after it.
   */
  private DeviceChange changeBy(
      UUID callerId, UUID id, Function<ClientEntity, DeviceChange> change) {
    ClientEntity caller;
    Optional<ClientEntity> target;
    if (callerId.equals(id)) {
      caller = clients.findForUpdate(callerId).orElseThrow();
      target = Optional.of(caller);
    } else if (callerId.compareTo(id) < 0) {
      caller = clients.findForUpdate(callerId).orElseThrow();
      target = clients.findForUpdate(id);
    } else {
      target = clients.findForUpdate(id);
      caller = clients.findForUpdate(callerId).orElseThrow();
    }
    if (caller.revoked()) {
      return new DeviceChange.Refused(Refusal.CALLER_REVOKED);
    }
    if (!caller.admin()) {
      return new DeviceChange.Refused(Refusal.NOT_AN_ADMIN);
    }
    return target.map(change).orElse(new DeviceChange.Refused(Refusal.UNKNOWN_CLIENT));
  }

  private DeviceChange done(ClientEntity client, boolean changed) {
    return new DeviceChange.Done(
        toManagedResponse(client, clients.pendingRetries(client.id())), changed);
  }

  /** Why a device's request to manage the others was refused. */
  enum Refusal {
    /** The caller was revoked after it authenticated. */
    CALLER_REVOKED,
    NOT_AN_ADMIN,
    UNKNOWN_CLIENT,
    CLIENT_REVOKED,
    CLIENT_IS_ADMIN
  }

  /** What {@link #listFor} found. */
  sealed interface DeviceList {
    record Listed(ClientList clients) implements DeviceList {}

    record Refused(Refusal refusal) implements DeviceList {}
  }

  /** What a device's change did; {@code changed} is false if the client already was as asked. */
  sealed interface DeviceChange {
    record Done(ManagedClientResponse client, boolean changed) implements DeviceChange {}

    record Refused(Refusal refusal) implements DeviceChange {}
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

  /** Replaces the client's push preferences. Empty if it was revoked after it authenticated. */
  @Transactional
  Optional<ClientResponse> setPushPreferences(UUID id, PushPreferences preferences) {
    return active(id)
        .map(
            client -> {
              client.setPushPreferences(preferences);
              LOG.infof("Client %s set its push preferences: %s", id, preferences);
              return toResponse(client);
            });
  }

  /** Where to push for this client: empty if it is unknown, revoked, or has no push target. */
  @Transactional
  public Optional<PushAddress> pushTargetOf(UUID id) {
    return clients
        .findByIdOptional(id)
        .filter(client -> !client.revoked() && client.pushProvider() != null)
        .map(client -> new PushAddress(client.pushProvider(), client.pushToken()));
  }

  /** The clients that have a push target (so are not revoked), oldest first. */
  @Transactional
  public List<PushRecipient> pushRecipients() {
    return clients.list("pushProvider is not null", Sort.by("createdAt").and("id")).stream()
        .map(client -> new PushRecipient(client.id(), client.pushPreferences()))
        .toList();
  }

  /** The client as a push recipient: empty if it is unknown, revoked, or has no push target. */
  @Transactional
  public Optional<PushRecipient> pushRecipient(UUID id) {
    return clients
        .findByIdOptional(id)
        .filter(client -> !client.revoked() && client.pushProvider() != null)
        .map(client -> new PushRecipient(client.id(), client.pushPreferences()));
  }

  /**
   * Removes the client's push target after its provider rejected it for good, but only if it is
   * still the given one: the client may have registered a new target since. True if removed.
   */
  @Transactional
  public boolean dropPushTarget(UUID id, PushAddress rejected) {
    return clients
        .findForUpdate(id)
        .filter(client -> rejected.provider().equals(client.pushProvider()))
        .filter(client -> rejected.token().equals(client.pushToken()))
        .map(
            client -> {
              client.clearPushTarget();
              return true;
            })
        .orElse(false);
  }

  /**
   * Records the result of a send to the client for the operator, overwriting the last success or
   * the last failure. A send that found no push target sent nothing and is not recorded. Revoked
   * clients keep their results.
   */
  @Transactional
  public void recordPushResult(UUID id, UUID eventId, DeliveryResult result) {
    switch (result) {
      case DELIVERED -> clients.recordPushSuccess(id, eventId, now());
      case NO_TARGET -> {}
      case UNSUPPORTED_PROVIDER, INVALID_TARGET, TRANSIENT_FAILURE, PERMANENT_FAILURE ->
          clients.recordPushFailure(id, eventId, result, now());
    }
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
        client.id(),
        client.name(),
        client.admin(),
        client.createdAt(),
        client.revokedAt(),
        pushTarget,
        client.pushPreferences());
  }

  private static ManagedClientResponse toManagedResponse(ClientEntity client, long pendingRetries) {
    return ManagedClientResponse.of(
        toResponse(client),
        new PushStatus(client.lastPushSuccess(), client.lastPushFailure(), pendingRetries));
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
