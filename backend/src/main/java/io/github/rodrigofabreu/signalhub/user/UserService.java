package io.github.rodrigofabreu.signalhub.user;

import io.github.rodrigofabreu.signalhub.client.ClientService;
import io.github.rodrigofabreu.signalhub.client.IssuedPairing;
import io.github.rodrigofabreu.signalhub.client.PairingService;
import io.github.rodrigofabreu.signalhub.producer.ProducerService;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.jboss.logging.Logger;

/**
 * Invites, renames, changes the role of and revokes users, for the operator. Logs only user IDs and
 * roles, never names of devices, keys or tokens.
 */
@ApplicationScoped
public class UserService {

  private static final Logger LOG = Logger.getLogger(UserService.class);

  private final UserRepository users;
  private final ClientService clients;
  private final ProducerService producers;
  private final EntityManager entityManager;
  private final PairingService pairings;

  UserService(
      UserRepository users,
      ClientService clients,
      ProducerService producers,
      EntityManager entityManager,
      PairingService pairings) {
    this.users = users;
    this.clients = clients;
    this.producers = producers;
    this.entityManager = entityManager;
    this.pairings = pairings;
  }

  /** Invites a user; empty if another user has this name. */
  @Transactional
  Optional<UserResponse> create(String name, Role role) {
    if (users.nameTaken(name, new UUID(0, 0))) {
      return Optional.empty();
    }
    var user = new UserEntity(name, role, now());
    users.persist(user);
    users.flush();
    LOG.infof("Invited user %s as %s", user.id(), role);
    return Optional.of(summarize(List.of(user)).getFirst());
  }

  @Transactional
  Optional<UserResponse> get(UUID id) {
    return users.findByIdOptional(id).map(user -> summarize(List.of(user)).getFirst());
  }

  /** Every user, oldest first. Four queries in total, whatever the number of users. */
  @Transactional
  List<UserResponse> list() {
    return summarize(users.listAll(Sort.by("createdAt").and("id")));
  }

  /**
   * Renames the user and sets their role; a null leaves that field as it is. Empty if no user has
   * this ID. A revoked user never changes.
   */
  @Transactional
  Optional<Update> update(UUID id, String name, Role role) {
    return users
        .findForUpdate(id)
        .map(
            user -> {
              if (user.revoked()) {
                return new Update.Revoked();
              }
              if (name != null && !name.equals(user.name()) && users.nameTaken(name, user.id())) {
                return new Update.NameTaken();
              }
              if (name != null && !name.equals(user.name())) {
                user.rename(name);
                LOG.infof("Renamed user %s", id);
              }
              if (role != null && role != user.role()) {
                user.setRole(role);
                LOG.infof("User %s is now %s", id, role);
              }
              users.flush();
              return new Update.Updated(summarize(List.of(user)).getFirst());
            });
  }

  /** What {@link #update} did to a user that exists. */
  sealed interface Update {
    record Updated(UserResponse user) implements Update {}

    record Revoked() implements Update {}

    record NameTaken() implements Update {}
  }

  /**
   * Revokes the user permanently: every device of theirs is revoked, so their keys stop working,
   * and their producers are disabled. Their events stay. An admin is no longer one. Idempotent.
   * Locks the user first, as redeeming a pairing does, so a device cannot be paired for a user
   * while they are being revoked.
   */
  @Transactional
  Optional<UserResponse> revoke(UUID id) {
    return users
        .findForUpdate(id)
        .map(
            user -> {
              user.revoke(now());
              clients.revokeAllOf(id);
              producers.disableAllOwnedBy(id);
              users.flush();
              LOG.infof("Revoked user %s", id);
              return summarize(List.of(user)).getFirst();
            });
  }

  /**
   * An admin's device invites a user as BASIC or MOD and creates their first pairing code, in one
   * transaction: either both exist or neither. Locks the caller's user and reads their role under
   * the lock, so an operator demoting or revoking them meanwhile applies before this or after it.
   *
   * @throws Refused if the caller may not, or the invitation is not valid
   */
  @Transactional
  Invited inviteBy(
      UUID callerUserId, UUID callerClientId, String name, Role role, String deviceName) {
    requireAdmin(callerUserId);
    requireAssignable(role);
    if (users.nameTaken(name, new UUID(0, 0))) {
      throw new Refused(Refusal.NAME_TAKEN);
    }
    var user = new UserEntity(name, role, now());
    users.persist(user);
    users.flush();
    var pairing =
        pairings
            .createForInvited(callerClientId, deviceName, user.id())
            .orElseThrow(() -> new Refused(Refusal.CALLER_REVOKED));
    LOG.infof("User %s invited user %s as %s", callerUserId, user.id(), role);
    return new Invited(user.ref(), pairing);
  }

  /**
   * An admin's device sets the role of a user who is not an admin to BASIC or MOD. Making a user an
   * admin, or no longer one, stays with the operator.
   *
   * @throws Refused if the caller may not, the user is unknown, revoked or an admin
   */
  @Transactional
  UserRef setRoleBy(UUID callerUserId, UUID id, Role role) {
    requireAdmin(callerUserId);
    requireAssignable(role);
    var user = users.findForUpdate(id).orElseThrow(() -> new Refused(Refusal.UNKNOWN_USER));
    if (user.revoked()) {
      throw new Refused(Refusal.USER_REVOKED);
    }
    if (user.role() == Role.ADMIN) {
      throw new Refused(Refusal.USER_IS_ADMIN);
    }
    if (user.role() != role) {
      user.setRole(role);
      LOG.infof("User %s made user %s %s", callerUserId, id, role);
    }
    users.flush();
    return user.ref();
  }

  /** The users who are not revoked, with their role and devices, by name ignoring case. */
  @Transactional
  List<DetailedUser> detailedActive() {
    var counts = new HashMap<UUID, long[]>();
    for (var row :
        rows(
            "SELECT user_id, count(*), count(*) FILTER (WHERE revoked_at IS NULL)"
                + " FROM clients GROUP BY user_id")) {
      counts.put(
          (UUID) row[0], new long[] {((Number) row[1]).longValue(), ((Number) row[2]).longValue()});
    }
    return users.list("revokedAt is null").stream()
        .sorted(Comparator.comparing(UserEntity::name, String.CASE_INSENSITIVE_ORDER))
        .map(
            user -> {
              var count = counts.getOrDefault(user.id(), new long[] {0, 0});
              return new DetailedUser(user.id(), user.name(), user.role(), count[1], count[0] > 0);
            })
        .toList();
  }

  /**
   * The producers a user who is not revoked owns, by name ignoring case.
   *
   * @throws Refused with UNKNOWN_USER if there is no such user or they are revoked
   */
  @Transactional
  List<PersonProducer> producersOf(UUID id) {
    var user = users.findByIdOptional(id).filter(found -> !found.revoked());
    if (user.isEmpty()) {
      throw new Refused(Refusal.UNKNOWN_USER);
    }
    List<?> found =
        entityManager
            .createNativeQuery(
                "SELECT id, name, visibility, disabled_at FROM producers WHERE owner_id = :owner"
                    + " ORDER BY lower(name), id")
            .setParameter("owner", id)
            .getResultList();
    return found.stream()
        .map(Object[].class::cast)
        .map(
            row ->
                new PersonProducer((UUID) row[0], (String) row[1], (String) row[2], row[3] != null))
        .toList();
  }

  /** A user invited from a device, with the code that pairs their first device. */
  record Invited(UserRef user, IssuedPairing pairing) {}

  /** Why a device's request about users was refused. */
  enum Refusal {
    /** The caller's user is not an admin. */
    NOT_ALLOWED,
    /** The caller, or its user, was revoked after it authenticated. */
    CALLER_REVOKED,
    /** ADMIN is not given from a device. */
    INVALID_ROLE,
    NAME_TAKEN,
    UNKNOWN_USER,
    USER_REVOKED,
    USER_IS_ADMIN
  }

  /** Thrown to refuse, which rolls the transaction back. Carries no stack trace. */
  static final class Refused extends RuntimeException {
    private static final long serialVersionUID = 1L;

    private final transient Refusal refusal;

    Refused(Refusal refusal) {
      super(refusal.name(), null, false, false);
      this.refusal = refusal;
    }

    Refusal refusal() {
      return refusal;
    }
  }

  /** The caller's user, locked, must still be an active admin. */
  private void requireAdmin(UUID callerUserId) {
    var caller =
        users
            .findForUpdate(callerUserId)
            .filter(user -> !user.revoked())
            .orElseThrow(() -> new Refused(Refusal.CALLER_REVOKED));
    if (caller.role() != Role.ADMIN) {
      throw new Refused(Refusal.NOT_ALLOWED);
    }
  }

  private static void requireAssignable(Role role) {
    if (role == Role.ADMIN) {
      throw new Refused(Refusal.INVALID_ROLE);
    }
  }

  private List<UserResponse> summarize(List<UserEntity> found) {
    var devices = new HashMap<UUID, List<UserResponse.Device>>();
    for (var row :
        rows("SELECT user_id, id, name, revoked_at FROM clients ORDER BY created_at, id")) {
      devices
          .computeIfAbsent((UUID) row[0], k -> new ArrayList<>())
          .add(new UserResponse.Device((UUID) row[1], (String) row[2], instant(row[3])));
    }
    var owned = new HashMap<UUID, List<UserResponse.Producer>>();
    for (var row :
        rows("SELECT owner_id, id, name, visibility, disabled_at FROM producers ORDER BY name")) {
      owned.computeIfAbsent((UUID) row[0], k -> new ArrayList<>()).add(producer(row));
    }
    var subscribed = new HashMap<UUID, List<UserResponse.Producer>>();
    for (var row :
        rows(
            "SELECT s.user_id, p.id, p.name, p.visibility, p.disabled_at FROM subscriptions s"
                + " JOIN producers p ON p.id = s.producer_id ORDER BY p.name")) {
      subscribed.computeIfAbsent((UUID) row[0], k -> new ArrayList<>()).add(producer(row));
    }
    return found.stream()
        .map(
            user ->
                new UserResponse(
                    user.id(),
                    user.name(),
                    user.role(),
                    user.createdAt(),
                    user.revokedAt(),
                    devices.getOrDefault(user.id(), List.of()),
                    owned.getOrDefault(user.id(), List.of()),
                    subscribed.getOrDefault(user.id(), List.of())))
        .toList();
  }

  private static UserResponse.Producer producer(Object[] row) {
    return new UserResponse.Producer(
        (UUID) row[1], (String) row[2], (String) row[3], instant(row[4]));
  }

  private List<Object[]> rows(String sql) {
    List<?> found = entityManager.createNativeQuery(sql).getResultList();
    return found.stream().map(Object[].class::cast).toList();
  }

  private static Instant instant(Object value) {
    if (value == null) {
      return null;
    }
    return value instanceof OffsetDateTime time ? time.toInstant() : (Instant) value;
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
