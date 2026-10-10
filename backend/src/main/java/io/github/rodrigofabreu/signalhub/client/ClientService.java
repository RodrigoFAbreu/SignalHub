package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.github.rodrigofabreu.signalhub.push.DeliveryResult;
import io.github.rodrigofabreu.signalhub.user.Role;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import io.github.rodrigofabreu.signalhub.user.UserRef;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import java.util.function.BiFunction;
import java.util.function.Function;
import java.util.stream.Collectors;
import org.hibernate.id.uuid.UuidVersion7Strategy;
import org.jboss.logging.Logger;

/**
 * Registers, revokes and deletes clients, authenticates client keys, and records push targets and
 * push preferences. Logs only client IDs and provider names, never keys, hashes or push tokens.
 */
@ApplicationScoped
public class ClientService {

  private static final Logger LOG = Logger.getLogger(ClientService.class);

  // Compared against when no client has the presented ID, so an unknown ID costs the same hash
  // comparison as a wrong secret.
  private static final byte[] NO_HASH = new byte[ApiKeys.HASH_BYTES];

  private final ClientRepository clients;
  private final UserDirectory users;

  ClientService(ClientRepository clients, UserDirectory users) {
    this.clients = clients;
    this.users = users;
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
    var user = users.find(client.get().userId()).filter(u -> users.isActive(u.id()));
    if (user.isEmpty()) {
      LOG.debugf("Rejected client credential: the user of client %s is revoked", clientId.get());
      return Optional.empty();
    }
    return Optional.of(
        new ClientIdentity(
            client.get().id(), client.get().name(), user.get().id(), user.get().role()));
  }

  /**
   * Registers a client for the user and issues its key, which is returned only here. Empty if the
   * user does not exist or is revoked. Locks the user, so a user being revoked gets no new device.
   */
  @Transactional
  Optional<IssuedClientKey> create(UUID userId, String name) {
    var user = users.lockActive(userId);
    if (user.isEmpty()) {
      return Optional.empty();
    }
    // The ID is part of the key, so it is generated here rather than on persist; same UUIDv7
    // generator Hibernate uses for the other tables.
    var id = UuidVersion7Strategy.INSTANCE.generateUuid(null);
    var key = ClientKeys.generate(id);
    var client = new ClientEntity(id, name, userId, ApiKeys.hash(key), now());
    clients.persist(client);
    LOG.infof("Registered client %s for user %s", id, userId);
    return Optional.of(new IssuedClientKey(toResponse(client, user.get()), key));
  }

  /** The client and its latest push results. */
  @Transactional
  Optional<ManagedClientResponse> get(UUID id) {
    return clients
        .findByIdOptional(id)
        .map(client -> toManagedResponse(client, clients.pendingRetries(id), userOf(client)));
  }

  /** All clients, oldest first, and their latest push results. */
  @Transactional
  List<ManagedClientResponse> list() {
    return list(clients.listAll(Sort.by("createdAt").and("id")));
  }

  private List<ManagedClientResponse> list(List<ClientEntity> found) {
    var pendingRetries = clients.pendingRetries();
    var owners = users.find(found.stream().map(ClientEntity::userId).collect(Collectors.toSet()));
    return found.stream()
        .map(
            client ->
                toManagedResponse(
                    client,
                    pendingRetries.getOrDefault(client.id(), 0L),
                    owners.get(client.userId())))
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
              return toResponse(client, userOf(client));
            });
  }

  /** Revokes every client of the user; the user is being revoked. Their push targets go too. */
  @Transactional
  public void revokeAllOf(UUID userId) {
    clients.revokeAllOf(userId, now());
    LOG.infof("Revoked every client of user %s", userId);
  }

  /**
   * Deletes a revoked client, and with it everything that exists only for it: its push retries and
   * the unused pairing codes it created. Events are not the client's and stay. Empty if no client
   * has this ID; an active client is not deleted, as it must be revoked first.
   */
  @Transactional
  Optional<Deletion> delete(UUID id) {
    return clients
        .findForUpdate(id)
        .map(
            client -> {
              if (!client.revoked()) {
                return Deletion.NOT_REVOKED;
              }
              clients.delete(client);
              LOG.infof("Deleted client %s", id);
              return Deletion.DELETED;
            });
  }

  /** What {@link #delete} did to a client that exists. */
  enum Deletion {
    DELETED,
    NOT_REVOKED
  }

  /**
   * Renames the client; a null name leaves it as it is. Empty if no client has this ID. A revoked
   * client never changes: it is not a device of anyone's any more. {@code admin}, if given, must be
   * what the client is already, as roles are set per user: a different value changes nothing and is
   * refused.
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
              var user = userOf(client);
              if (admin != null && admin != user.admin()) {
                return new Update.RolesArePerUser();
              }
              if (name != null && !name.equals(client.name())) {
                client.rename(name);
                LOG.infof("Renamed client %s", id);
              }
              return new Update.Updated(
                  toManagedResponse(client, clients.pendingRetries(id), user));
            });
  }

  /** What {@link #update} did to a client that exists. */
  sealed interface Update {
    record Updated(ManagedClientResponse client) implements Update {}

    record Revoked() implements Update {}

    /** The request asked for an admin flag the client's user does not have. */
    record RolesArePerUser() implements Update {}
  }

  /**
   * The devices a device may see, if it is active: every device when its user is an admin, else its
   * user's own. Nothing changes, so the caller is not locked.
   */
  @Transactional
  DeviceList listFor(UUID callerId) {
    var caller = clients.findByIdOptional(callerId).orElseThrow();
    if (caller.revoked()) {
      return new DeviceList.Refused(Refusal.CALLER_REVOKED);
    }
    if (userOf(caller).admin()) {
      return new DeviceList.Listed(new ClientList(list()));
    }
    var own = clients.list("userId", Sort.by("createdAt").and("id"), caller.userId());
    return new DeviceList.Listed(new ClientList(list(own)));
  }

  /**
   * A device revokes a device, as its user's role allows. A mod revokes their own devices, but not
   * their last active one, so they cannot lock themselves out; an admin revokes the devices of
   * users who are not admins; a basic user revokes none. Revoking a revoked device changes nothing.
   * The devices of admins are revoked only with the admin token.
   */
  @Transactional
  DeviceChange revokeBy(UUID callerId, UUID id) {
    return changeBy(
        callerId,
        id,
        (caller, client) -> {
          var refusal = scopeRefusal(caller, client);
          if (refusal != null) {
            return new DeviceChange.Refused(refusal);
          }
          if (client.revoked()) {
            return done(client, false);
          }
          if (caller.user().role() == Role.MOD
              && clients.countActive(caller.client().userId()) <= 1) {
            return new DeviceChange.Refused(Refusal.LAST_DEVICE);
          }
          client.revoke(now());
          LOG.infof("Client %s revoked client %s", callerId, id);
          return done(client, true);
        },
        DeviceChange.Refused::new);
  }

  /**
   * A device deletes a revoked device, as its user's role allows: a mod their own, an admin those
   * of users who are not admins. Empty once deleted; an active device, the caller included, must be
   * revoked first.
   */
  @Transactional
  Optional<Refusal> deleteBy(UUID callerId, UUID id) {
    return changeBy(
        callerId,
        id,
        (caller, client) -> {
          var refusal = scopeRefusal(caller, client);
          if (refusal != null) {
            return Optional.of(refusal);
          }
          if (!client.revoked()) {
            return Optional.of(Refusal.CLIENT_NOT_REVOKED);
          }
          clients.delete(client);
          LOG.infof("Client %s deleted client %s", callerId, id);
          return Optional.<Refusal>empty();
        },
        Optional::of);
  }

  /**
   * Whether the caller's role reaches the target device: a mod only their own devices (any other is
   * unknown to them), an admin any device but those of admins. Null if it does.
   */
  private Refusal scopeRefusal(Caller caller, ClientEntity target) {
    if (caller.user().role() == Role.ADMIN) {
      return userOf(target).admin() ? Refusal.CLIENT_IS_ADMIN : null;
    }
    return target.userId().equals(caller.client().userId()) ? null : Refusal.UNKNOWN_CLIENT;
  }

  /** The device making a change, with its user as the role check read them. */
  record Caller(ClientEntity client, UserRef user) {}

  /**
   * Checks that the caller is an active device whose role allows device management before looking
   * at the target, so a basic user learns nothing about the others. Locks the caller's user first,
   * as revoking a user and redeeming a pairing do, then both clients in a fixed order so two
   * devices acting on each other cannot deadlock; holding the user's lock also serialises a user's
   * own changes, so two of a mod's devices cannot revoke each other. An operator revoking the
   * caller or its user meanwhile is applied before this change or after it.
   */
  private <T> T changeBy(
      UUID callerId,
      UUID id,
      BiFunction<Caller, ClientEntity, T> change,
      Function<Refusal, T> refused) {
    var unlocked = clients.findByIdOptional(callerId).orElseThrow();
    var user = users.lockActive(unlocked.userId());
    if (user.isEmpty()) {
      return refused.apply(Refusal.CALLER_REVOKED);
    }
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
      return refused.apply(Refusal.CALLER_REVOKED);
    }
    if (user.get().role() == Role.BASIC) {
      return refused.apply(Refusal.NOT_ALLOWED);
    }
    var asked = new Caller(caller, user.get());
    return target
        .map(client -> change.apply(asked, client))
        .orElseGet(() -> refused.apply(Refusal.UNKNOWN_CLIENT));
  }

  private DeviceChange done(ClientEntity client, boolean changed) {
    return new DeviceChange.Done(
        toManagedResponse(client, clients.pendingRetries(client.id()), userOf(client)), changed);
  }

  /** Why a device's request to manage devices was refused. */
  enum Refusal {
    /** The caller, or its user, was revoked after it authenticated. */
    CALLER_REVOKED,
    /** The caller's role does not allow it. */
    NOT_ALLOWED,
    UNKNOWN_CLIENT,
    CLIENT_IS_ADMIN,
    CLIENT_NOT_REVOKED,
    /** The caller is a mod and the device is their last active one. */
    LAST_DEVICE,
    /** No pairing with this ID that the caller created. */
    UNKNOWN_PAIRING,
    UNKNOWN_USER,
    USER_REVOKED
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
              return toResponse(client, userOf(client));
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
              return toResponse(client, userOf(client));
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
              return toResponse(client, userOf(client));
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
    var found = clients.list("pushProvider is not null", Sort.by("createdAt").and("id"));
    var owners = users.find(found.stream().map(ClientEntity::userId).collect(Collectors.toSet()));
    return found.stream().map(client -> recipient(client, owners.get(client.userId()))).toList();
  }

  /** The clients that are not revoked but have no push target, oldest first. */
  @Transactional
  public List<ClientOwner> withoutPushTarget() {
    return clients
        .list("revokedAt is null and pushProvider is null", Sort.by("createdAt").and("id"))
        .stream()
        .map(client -> new ClientOwner(client.id(), client.userId()))
        .toList();
  }

  /** The client as a push recipient: empty if it is unknown, revoked, or has no push target. */
  @Transactional
  public Optional<PushRecipient> pushRecipient(UUID id) {
    return clients
        .findByIdOptional(id)
        .filter(client -> !client.revoked() && client.pushProvider() != null)
        .map(client -> recipient(client, userOf(client)));
  }

  private static PushRecipient recipient(ClientEntity client, UserRef user) {
    return new PushRecipient(client.id(), user.id(), user.admin(), client.pushPreferences());
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
    var found = clients.findById(client.id());
    return toResponse(found, userOf(found));
  }

  private UserRef userOf(ClientEntity client) {
    // The foreign key guarantees the user exists.
    return users.find(client.userId()).orElseThrow();
  }

  private static ClientResponse toResponse(ClientEntity client, UserRef user) {
    var pushTarget =
        client.pushProvider() == null
            ? null
            : new ClientResponse.PushTarget(client.pushProvider(), client.pushUpdatedAt());
    return new ClientResponse(
        client.id(),
        client.name(),
        user.admin(),
        user,
        client.createdAt(),
        client.revokedAt(),
        pushTarget,
        client.pushPreferences());
  }

  private static ManagedClientResponse toManagedResponse(
      ClientEntity client, long pendingRetries, UserRef user) {
    return ManagedClientResponse.of(
        toResponse(client, user),
        new PushStatus(client.lastPushSuccess(), client.lastPushFailure(), pendingRetries));
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
