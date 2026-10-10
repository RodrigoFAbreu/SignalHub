package io.github.rodrigofabreu.signalhub.user;

import io.github.rodrigofabreu.signalhub.client.ClientService;
import io.github.rodrigofabreu.signalhub.producer.ProducerService;
import io.quarkus.panache.common.Sort;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
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

  UserService(
      UserRepository users,
      ClientService clients,
      ProducerService producers,
      EntityManager entityManager) {
    this.users = users;
    this.clients = clients;
    this.producers = producers;
    this.entityManager = entityManager;
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
