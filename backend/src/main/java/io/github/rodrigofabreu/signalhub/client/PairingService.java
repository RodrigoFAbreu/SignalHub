package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.github.rodrigofabreu.signalhub.user.Role;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
import io.github.rodrigofabreu.signalhub.user.UserRef;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;
import org.hibernate.id.uuid.UuidVersion7Strategy;
import org.jboss.logging.Logger;

/**
 * Creates pairings and redeems them into clients. Logs only pairing and client IDs, never codes,
 * keys or hashes.
 */
@ApplicationScoped
class PairingService {

  private static final Logger LOG = Logger.getLogger(PairingService.class);

  // Long enough to open the app and scan the code; short enough that a code photographed or left
  // on a screen is soon useless.
  static final Duration LIFETIME = Duration.ofMinutes(10);

  // How long a pairing is kept after it expires, used or not, so whoever shows the code can still
  // tell used from expired: a page polls only while the code is shown, but its clock, or a poll in
  // flight at expiry, may be late.
  static final Duration KEPT_AFTER_EXPIRY = Duration.ofMinutes(10);

  private final PairingRepository pairings;
  private final ClientService clients;
  private final ClientRepository clientRows;
  private final PairingUris uris;
  private final UserDirectory users;

  PairingService(
      PairingRepository pairings,
      ClientService clients,
      ClientRepository clientRows,
      PairingUris uris,
      UserDirectory users) {
    this.pairings = pairings;
    this.clients = clients;
    this.clientRows = clientRows;
    this.uris = uris;
    this.users = users;
  }

  /**
   * Creates a pairing for a new client of this name that belongs to the user; its code is returned
   * only here. Empty if the user does not exist or is revoked.
   */
  @Transactional
  Optional<IssuedPairing> create(String clientName, UUID userId) {
    deleteExpired();
    var user = users.find(userId).filter(found -> users.isActive(found.id()));
    if (user.isEmpty()) {
      return Optional.empty();
    }
    var issued = issue(clientName, user.get(), null);
    LOG.infof(
        "Created pairing %s for user %s, expires at %s", issued.id(), userId, issued.expiresAt());
    return Optional.of(issued);
  }

  /**
   * A device creates a pairing for a new client of this name, as its user's role allows: a mod for
   * their own user, an admin for any user who is not revoked, a basic user for none. The new device
   * is an admin device exactly when that user is an admin. Locks the caller, so an operator
   * revoking it meanwhile is applied before this or after it.
   */
  @Transactional
  DevicePairing createBy(UUID callerId, String clientName, UUID requestedUserId) {
    // Before the caller's lock: a redemption holds its pairing's lock while it waits for the lock
    // of the device that created it, so taking them the other way round could deadlock.
    deleteExpired();
    var caller = clientRows.findForUpdate(callerId).orElseThrow();
    if (caller.revoked()) {
      return new DevicePairing.Refused(ClientService.Refusal.CALLER_REVOKED);
    }
    var role = users.find(caller.userId()).orElseThrow().role();
    var userId = requestedUserId == null ? caller.userId() : requestedUserId;
    if (!mayPairFor(role, caller.userId(), userId)) {
      return new DevicePairing.Refused(ClientService.Refusal.NOT_ALLOWED);
    }
    var user = users.find(userId);
    if (user.isEmpty()) {
      return new DevicePairing.Refused(ClientService.Refusal.UNKNOWN_USER);
    }
    if (!users.isActive(userId)) {
      return new DevicePairing.Refused(ClientService.Refusal.USER_REVOKED);
    }
    var issued = issue(clientName, user.get(), callerId);
    LOG.infof(
        "Client %s created pairing %s for user %s, expires at %s",
        callerId, issued.id(), userId, issued.expiresAt());
    return new DevicePairing.Created(issued);
  }

  /** A mod pairs for themselves, an admin for anyone, a basic user for no one. */
  private static boolean mayPairFor(Role role, UUID creatorUserId, UUID userId) {
    return switch (role) {
      case ADMIN -> true;
      case MOD -> creatorUserId.equals(userId);
      case BASIC -> false;
    };
  }

  /** What {@link #createBy} did. */
  sealed interface DevicePairing {
    record Created(IssuedPairing pairing) implements DevicePairing {}

    record Refused(ClientService.Refusal refusal) implements DevicePairing {}
  }

  /** Whether the operator's pairing was used; empty if it is unknown or a device's. */
  @Transactional
  Optional<PairingStatus> status(UUID id) {
    return pairings.findByOperator(id).map(this::status);
  }

  /**
   * Whether a pairing this device created was used, if the caller is an active device of a mod or
   * an admin; otherwise why not. Checked before the pairing is looked up, so a basic user learns
   * nothing about it. Another device's pairing, and the operator's, are unknown to it.
   */
  @Transactional
  PairingLookup statusFor(UUID callerId, UUID id) {
    var caller = clientRows.findByIdOptional(callerId).orElseThrow();
    if (caller.revoked()) {
      return new PairingLookup.Refused(ClientService.Refusal.CALLER_REVOKED);
    }
    if (users.find(caller.userId()).orElseThrow().role() == Role.BASIC) {
      return new PairingLookup.Refused(ClientService.Refusal.NOT_ALLOWED);
    }
    return pairings
        .findByCreator(id, callerId)
        .<PairingLookup>map(pairing -> new PairingLookup.Found(status(pairing)))
        .orElseGet(() -> new PairingLookup.Refused(ClientService.Refusal.UNKNOWN_PAIRING));
  }

  /** What {@link #statusFor} found. */
  sealed interface PairingLookup {
    record Found(PairingStatus status) implements PairingLookup {}

    record Refused(ClientService.Refusal refusal) implements PairingLookup {}
  }

  private PairingStatus status(PairingEntity pairing) {
    if (pairing.redeemedBy() != null) {
      // The client exists: deleting it deletes the pairing too.
      var client = clientRows.findById(pairing.redeemedBy());
      return new PairingStatus(
          pairing.id(),
          PairingStatus.State.REDEEMED,
          pairing.expiresAt(),
          pairing.redeemedAt(),
          new PairingStatus.PairedClient(client.id(), client.name()));
    }
    var state =
        pairing.expiresAt().isAfter(now())
            ? PairingStatus.State.PENDING
            : PairingStatus.State.EXPIRED;
    return new PairingStatus(pairing.id(), state, pairing.expiresAt(), null, null);
  }

  // Old pairings are cleared when a pairing is created rather than on a timer: they no longer
  // redeem either way, and are kept a while after they expire so their status can still be read.
  private void deleteExpired() {
    pairings.deleteExpiredBy(now().minus(KEPT_AFTER_EXPIRY));
  }

  private IssuedPairing issue(String clientName, UserRef user, UUID createdBy) {
    var now = now();
    var code = PairingCodes.generate();
    var pairing =
        new PairingEntity(
            UuidVersion7Strategy.INSTANCE.generateUuid(null),
            ApiKeys.hash(code),
            clientName,
            user.id(),
            now,
            now.plus(LIFETIME),
            createdBy);
    pairings.persist(pairing);
    return new IssuedPairing(
        pairing.id(),
        clientName,
        user.admin(),
        user,
        code,
        pairing.expiresAt(),
        uris.of(code).orElse(null));
  }

  /**
   * Registers the pairing's client for the pairing's user and issues its key, if the code is known,
   * unused and unexpired, and marks the pairing redeemed by that client so the code never works
   * again. Empty for a malformed, unknown, used or expired code, for a code whose user was revoked,
   * and for a code whose device was revoked since it created it, or whose user's role no longer
   * allows creating it: revoking a stolen device also stops the codes it handed out.
   */
  @Transactional
  Optional<Redeemed> redeem(String code) {
    if (!PairingCodes.isWellFormed(code)) {
      LOG.debug("Rejected pairing code: not a SignalHub pairing code");
      return Optional.empty();
    }
    var pairing = pairings.findForRedemption(ApiKeys.hash(code));
    if (pairing.isEmpty()) {
      LOG.debug("Rejected pairing code: unknown");
      return Optional.empty();
    }
    if (pairing.get().redeemedAt() != null) {
      LOG.debugf("Rejected pairing code: pairing %s already used", pairing.get().id());
      return Optional.empty();
    }
    if (!pairing.get().expiresAt().isAfter(now())) {
      LOG.debugf("Rejected pairing code: pairing %s expired", pairing.get().id());
      return Optional.empty();
    }
    // The user before the creator: the lock order is the pairing, the user, then clients.
    var user = users.lockActive(pairing.get().userId());
    if (user.isEmpty()) {
      pairings.delete(pairing.get());
      LOG.debugf(
          "Rejected pairing code: user %s of pairing %s is revoked",
          pairing.get().userId(), pairing.get().id());
      return Optional.empty();
    }
    ClientEntity creator = null;
    if (pairing.get().createdBy() != null) {
      creator = clientRows.findForUpdate(pairing.get().createdBy()).orElseThrow();
      var creatorRole = users.find(creator.userId()).orElseThrow().role();
      if (creator.revoked() || !mayPairFor(creatorRole, creator.userId(), user.get().id())) {
        // The code can never redeem again, and its creator can no longer ask about it.
        pairings.delete(pairing.get());
        LOG.debugf(
            "Rejected pairing code: client %s, which created pairing %s, may no longer create it",
            creator.id(), pairing.get().id());
        return Optional.empty();
      }
    }
    var issued = clients.create(user.get().id(), pairing.get().clientName()).orElseThrow();
    pairing.get().redeem(issued.client().id(), now());
    LOG.infof("Redeemed pairing %s as client %s", pairing.get().id(), issued.client().id());
    var paired =
        new ClientPaired(
            issued.client().id(),
            issued.client().name(),
            issued.client().admin(),
            user.get().id(),
            creator == null ? null : creator.id(),
            creator == null ? null : creator.name());
    return Optional.of(new Redeemed(issued, paired));
  }

  /** A redeemed pairing: the new client's key, and the notice to tell the owner's devices. */
  record Redeemed(IssuedClientKey issued, ClientPaired paired) {}

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
