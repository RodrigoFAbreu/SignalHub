package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.transaction.Transactional;
import java.time.Duration;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
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
  private final PairingUris uris;

  PairingService(PairingRepository pairings, ClientService clients, PairingUris uris) {
    this.pairings = pairings;
    this.clients = clients;
    this.uris = uris;
  }

  /**
   * Creates a pairing for a new client of this name, an admin device or not; its code is returned
   * only here.
   */
  @Transactional
  IssuedPairing create(String clientName, boolean admin) {
    var now = now();
    // Expired pairings are cleared here rather than on a timer: they no longer redeem either way.
    pairings.deleteExpired(now);
    var code = PairingCodes.generate();
    var pairing =
        new PairingEntity(
            UuidVersion7Strategy.INSTANCE.generateUuid(null),
            ApiKeys.hash(code),
            clientName,
            admin,
            now,
            now.plus(LIFETIME));
    pairings.persist(pairing);
    LOG.infof(
        "Created pairing %s%s, expires at %s",
        pairing.id(), admin ? " for an admin device" : "", pairing.expiresAt());
    return new IssuedPairing(
        clientName, admin, code, pairing.expiresAt(), uris.of(code).orElse(null));
  }

  /**
   * Registers the pairing's client and issues its key, if the code is known and unexpired, and
   * deletes the pairing so the code never works again. Empty for a malformed, unknown, used or
   * expired code.
   */
  @Transactional
  Optional<IssuedClientKey> redeem(String code) {
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
    var issued = clients.create(pairing.get().clientName(), pairing.get().admin());
    LOG.infof("Redeemed pairing %s as client %s", pairing.get().id(), issued.client().id());
    return Optional.of(issued);
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
