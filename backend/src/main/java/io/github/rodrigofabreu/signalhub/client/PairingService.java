package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
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

  private final PairingRepository pairings;
  private final ClientService clients;
  private final ClientRepository clientRows;
  private final PairingUris uris;

  PairingService(
      PairingRepository pairings,
      ClientService clients,
      ClientRepository clientRows,
      PairingUris uris) {
    this.pairings = pairings;
    this.clients = clients;
    this.clientRows = clientRows;
    this.uris = uris;
  }

  /**
   * Creates a pairing for a new client of this name, an admin device or not; its code is returned
   * only here.
   */
  @Transactional
  IssuedPairing create(String clientName, boolean admin) {
    deleteExpired();
    var issued = issue(clientName, admin, null);
    LOG.infof(
        "Created pairing %s%s, expires at %s",
        issued.id(), admin ? " for an admin device" : "", issued.pairing().expiresAt());
    return issued.pairing();
  }

  /**
   * An admin device creates a pairing for a new client of this name, never an admin device: a
   * leaked code must not hand out admin rights, and making the paired device an admin is a separate
   * step the owner's devices are told about. Locks the caller, so an operator revoking it or taking
   * its rights away meanwhile is applied before this or after it.
   */
  @Transactional
  DevicePairing createBy(UUID callerId, String clientName) {
    // Before the caller's lock: a redemption holds its pairing's lock while it waits for the lock
    // of the device that created it, so taking them the other way round could deadlock.
    deleteExpired();
    var caller = clientRows.findForUpdate(callerId).orElseThrow();
    if (caller.revoked()) {
      return new DevicePairing.Refused(ClientService.Refusal.CALLER_REVOKED);
    }
    if (!caller.admin()) {
      return new DevicePairing.Refused(ClientService.Refusal.NOT_AN_ADMIN);
    }
    var issued = issue(clientName, false, callerId);
    LOG.infof(
        "Client %s created pairing %s, expires at %s",
        callerId, issued.id(), issued.pairing().expiresAt());
    return new DevicePairing.Created(issued.pairing());
  }

  /** What {@link #createBy} did. */
  sealed interface DevicePairing {
    record Created(IssuedPairing pairing) implements DevicePairing {}

    record Refused(ClientService.Refusal refusal) implements DevicePairing {}
  }

  private record Issued(UUID id, IssuedPairing pairing) {}

  // Expired pairings are cleared when a pairing is created rather than on a timer: they no longer
  // redeem either way.
  private void deleteExpired() {
    pairings.deleteExpired(now());
  }

  private Issued issue(String clientName, boolean admin, UUID createdBy) {
    var now = now();
    var code = PairingCodes.generate();
    var pairing =
        new PairingEntity(
            UuidVersion7Strategy.INSTANCE.generateUuid(null),
            ApiKeys.hash(code),
            clientName,
            admin,
            now,
            now.plus(LIFETIME),
            createdBy);
    pairings.persist(pairing);
    return new Issued(
        pairing.id(),
        new IssuedPairing(
            clientName, admin, code, pairing.expiresAt(), uris.of(code).orElse(null)));
  }

  /**
   * Registers the pairing's client and issues its key, if the code is known and unexpired, and
   * deletes the pairing so the code never works again. Empty for a malformed, unknown, used or
   * expired code, and for a code whose admin device was revoked or is no longer an admin since it
   * created it: revoking a stolen admin device also stops the codes it handed out.
   */
  @Transactional
  Optional<Redeemed> redeem(String code) {
    if (!PairingCodes.isWellFormed(code)) {
      LOG.debug("Rejected pairing code: not a SignalHub pairing code");
      return Optional.empty();
    }
    var pairing = pairings.findForRedemption(ApiKeys.hash(code));
    if (pairing.isEmpty()) {
      LOG.debug("Rejected pairing code: unknown or already used");
      return Optional.empty();
    }
    if (!pairing.get().expiresAt().isAfter(now())) {
      LOG.debugf("Rejected pairing code: pairing %s expired", pairing.get().id());
      return Optional.empty();
    }
    pairings.delete(pairing.get());
    ClientEntity creator = null;
    if (pairing.get().createdBy() != null) {
      creator = clientRows.findForUpdate(pairing.get().createdBy()).orElseThrow();
      if (creator.revoked() || !creator.admin()) {
        // Deleted all the same: the code can never redeem again.
        LOG.debugf(
            "Rejected pairing code: client %s, which created pairing %s, is no longer an active"
                + " admin device",
            creator.id(), pairing.get().id());
        return Optional.empty();
      }
    }
    var issued = clients.create(pairing.get().clientName(), pairing.get().admin());
    LOG.infof("Redeemed pairing %s as client %s", pairing.get().id(), issued.client().id());
    var paired =
        new ClientPaired(
            issued.client().id(),
            issued.client().name(),
            issued.client().admin(),
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
