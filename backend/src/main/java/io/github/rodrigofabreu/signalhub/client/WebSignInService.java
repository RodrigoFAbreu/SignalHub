package io.github.rodrigofabreu.signalhub.client;

import io.github.rodrigofabreu.signalhub.producer.ApiKeys;
import io.github.rodrigofabreu.signalhub.user.UserDirectory;
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
 * Signs a browser in from a device. The page starts a sign-in and shows its codes; a device of the
 * user looks a code up, asks the user, and approves or cancels; the page's next poll collects a new
 * browser client and its session key, once. Logs only IDs, never codes, keys or hashes.
 *
 * <p>Nobody who is not already signed in on a device can approve, and approving needs a code that
 * is only on the page's screen, so a wrong or abandoned sign-in gives no one a session.
 */
@ApplicationScoped
public class WebSignInService {

  private static final Logger LOG = Logger.getLogger(WebSignInService.class);

  /** How long a page's codes work; the page shows a countdown and asks for fresh ones itself. */
  static final Duration LIFETIME = Duration.ofMinutes(3);

  /** Once approved, how long the page has to collect its session. */
  static final Duration COLLECT_WITHIN = Duration.ofMinutes(2);

  // Long enough that a poll in flight at expiry, or a late page clock, still reads its answer.
  static final Duration KEPT_AFTER_EXPIRY = Duration.ofMinutes(10);

  /** Sign-ins waiting at once, so unauthenticated pages cannot fill the table. */
  static final int MAX_OPEN = 200;

  /** Wrong codes one device may try, and all devices together, in {@link #TRY_WINDOW}. */
  static final int MAX_WRONG_PER_DEVICE = 5;

  static final int MAX_WRONG_IN_TOTAL = 30;
  static final Duration TRY_WINDOW = Duration.ofMinutes(10);

  private final WebSignInRepository signIns;
  private final ClientService clients;
  private final ClientRepository clientRows;
  private final UserDirectory users;
  private final PairingUris uris;
  private final AttemptLimiter<UUID> wrongByDevice =
      new AttemptLimiter<>(MAX_WRONG_PER_DEVICE, TRY_WINDOW);
  private final AttemptLimiter<String> wrongInTotal =
      new AttemptLimiter<>(MAX_WRONG_IN_TOTAL, TRY_WINDOW);

  WebSignInService(
      WebSignInRepository signIns,
      ClientService clients,
      ClientRepository clientRows,
      UserDirectory users,
      PairingUris uris) {
    this.signIns = signIns;
    this.clients = clients;
    this.clientRows = clientRows;
    this.users = users;
    this.uris = uris;
  }

  /** A new sign-in, and the secrets only here: the page's poll secret and the codes it shows. */
  record Started(
      UUID id,
      String pollSecret,
      String code,
      String scanCode,
      String uri,
      Instant startedAt,
      Instant expiresAt,
      String browserName) {

    // The default record toString would print the secrets if this were ever logged.
    @Override
    public String toString() {
      return "Started[id=" + id + "]";
    }
  }

  /** Starts a sign-in for a browser the {@code User-Agent} describes; empty if too many wait. */
  @Transactional
  Optional<Started> start(String userAgent) {
    var now = now();
    signIns.deleteExpiredBy(now.minus(KEPT_AFTER_EXPIRY));
    if (signIns.countOpen(now) >= MAX_OPEN) {
      return Optional.empty();
    }
    var typed = WebSignInCodes.typed();
    var scan = WebSignInCodes.scan();
    var poll = WebSignInCodes.poll();
    var name = BrowserNames.of(userAgent);
    var signIn =
        new WebSignInEntity(
            UuidVersion7Strategy.INSTANCE.generateUuid(null),
            ApiKeys.hash(poll),
            ApiKeys.hash(typed),
            ApiKeys.hash(scan),
            name,
            now,
            now.plus(LIFETIME));
    // The six characters can repeat across live sign-ins; a collision is vanishingly rare, and the
    // unique index makes the page ask again rather than two pages share a code.
    signIns.persist(signIn);
    signIns.flush();
    LOG.infof("Started web sign-in %s", signIn.id());
    return Optional.of(
        new Started(
            signIn.id(),
            poll,
            WebSignInCodes.display(typed),
            scan,
            uris.signIn(scan).orElse(null),
            now,
            signIn.expiresAt(),
            name));
  }

  /** Where a sign-in is, as the page reads it. */
  enum State {
    PENDING,
    ASKED,
    SIGNED_IN,
    CANCELLED,
    EXPIRED
  }

  /**
   * What a poll found. {@code key} is the new browser's session key, set exactly once, on the poll
   * that signs the browser in, together with {@code signedIn}, the notice to tell the user's
   * devices.
   */
  record Polled(State state, Instant expiresAt, String key, BrowserSignedIn signedIn) {

    @Override
    public String toString() {
      return "Polled[state=" + state + "]";
    }
  }

  /**
   * The state of the sign-in for the page that holds its poll secret; empty if the ID is unknown or
   * the secret wrong (the same answer for both). If a device approved it, this poll creates the
   * browser client and returns its key, and a later one finds the sign-in used.
   */
  @Transactional
  Optional<Polled> poll(UUID id, String pollSecret) {
    var found =
        signIns
            .findForUpdate(id)
            .filter(
                signIn ->
                    WebSignInCodes.isWellFormedPoll(pollSecret)
                        && ApiKeys.hashesMatch(signIn.pollHash(), ApiKeys.hash(pollSecret)));
    if (found.isEmpty()) {
      return Optional.empty();
    }
    var signIn = found.get();
    var now = now();
    var expired = !signIn.expiresAt().isAfter(now);
    return Optional.of(
        switch (signIn.status()) {
          case PENDING ->
              new Polled(expired ? State.EXPIRED : State.PENDING, signIn.expiresAt(), null, null);
          case ASKED ->
              new Polled(expired ? State.EXPIRED : State.ASKED, signIn.expiresAt(), null, null);
          case CANCELLED -> new Polled(State.CANCELLED, signIn.expiresAt(), null, null);
          case SIGNED_IN -> new Polled(State.EXPIRED, signIn.expiresAt(), null, null);
          case APPROVED -> expired ? expired(signIn) : signIn(signIn, now);
        });
  }

  private Polled expired(WebSignInEntity signIn) {
    return new Polled(State.EXPIRED, signIn.expiresAt(), null, null);
  }

  private Polled signIn(WebSignInEntity signIn, Instant now) {
    var asker = clientRows.findById(signIn.askedBy());
    // Empty if the user was revoked meanwhile: no browser is signed in for them.
    var issued =
        clients.create(
            signIn.userId(), signIn.browserName(), ClientKind.BROWSER, endOfSession(now));
    if (issued.isEmpty()) {
      signIn.cancel();
      return new Polled(State.CANCELLED, signIn.expiresAt(), null, null);
    }
    signIn.signedIn();
    var client = issued.get().client();
    LOG.infof(
        "Web sign-in %s signed in browser %s for user %s, approved by client %s",
        signIn.id(), client.id(), signIn.userId(), asker.id());
    return new Polled(
        State.SIGNED_IN,
        client.expiresAt(),
        issued.get().clientKey(),
        new BrowserSignedIn(client.id(), client.name(), signIn.userId(), asker.id(), asker.name()));
  }

  private static Instant endOfSession(Instant now) {
    return now.plus(WebSession.LIFETIME);
  }

  /** A device asked to sign the browser behind a code in: what to show its user. */
  record Asked(UUID id, String browserName, Instant expiresAt) {}

  /** What a device's lookup of a code found. */
  sealed interface Lookup {
    record Found(Asked asked) implements Lookup {}

    /** No live sign-in has this code. Counted against the device. */
    record Unknown() implements Lookup {}

    /** The device, or every device together, tried too many wrong codes lately. */
    record TooManyTries() implements Lookup {}
  }

  /**
   * A device looks a typed or scanned code up and becomes the one that may approve or cancel that
   * sign-in. Wrong codes are bounded per device and in total; a device that has used its tries is
   * refused before the code is looked at, so a right guess cannot be told from a wrong one.
   */
  @Transactional
  Lookup ask(UUID deviceId, String entered) {
    var now = now();
    if (wrongByDevice.blocked(deviceId, now) || wrongInTotal.blocked("all", now)) {
      LOG.debugf("Refused a code lookup by client %s: too many wrong tries", deviceId);
      return new Lookup.TooManyTries();
    }
    var found =
        signIns
            .findByCodeForUpdate(ApiKeys.hash(WebSignInCodes.normalise(entered)))
            .filter(
                signIn ->
                    (signIn.status() == WebSignInEntity.Status.PENDING
                            || signIn.status() == WebSignInEntity.Status.ASKED)
                        && signIn.expiresAt().isAfter(now));
    if (found.isEmpty()) {
      wrongByDevice.fail(deviceId, now);
      wrongInTotal.fail("all", now);
      return new Lookup.Unknown();
    }
    found.get().ask(deviceId);
    LOG.infof("Client %s looked up web sign-in %s", deviceId, found.get().id());
    return new Lookup.Found(
        new Asked(found.get().id(), found.get().browserName(), found.get().expiresAt()));
  }

  /** What approving or cancelling did. */
  enum Outcome {
    DONE,
    /** Not a live sign-in this device asked about. */
    UNKNOWN,
    /** The device's user was revoked meanwhile. */
    REFUSED
  }

  /** The device's user approves signing the browser in. The page's next poll collects it. */
  @Transactional
  Outcome approve(UUID deviceId, UUID id) {
    var now = now();
    var found = askedBy(deviceId, id, now);
    if (found.isEmpty()) {
      return Outcome.UNKNOWN;
    }
    var device = clientRows.findById(deviceId);
    if (users.lockActive(device.userId()).isEmpty()) {
      return Outcome.REFUSED;
    }
    found.get().approve(device.userId(), now.plus(COLLECT_WITHIN));
    LOG.infof("Client %s approved web sign-in %s", deviceId, id);
    return Outcome.DONE;
  }

  /** The device's user declines; the page learns it is cancelled. */
  @Transactional
  Outcome cancel(UUID deviceId, UUID id) {
    var found = askedBy(deviceId, id, now());
    if (found.isEmpty()) {
      return Outcome.UNKNOWN;
    }
    found.get().cancel();
    LOG.infof("Client %s cancelled web sign-in %s", deviceId, id);
    return Outcome.DONE;
  }

  private Optional<WebSignInEntity> askedBy(UUID deviceId, UUID id, Instant now) {
    return signIns
        .findForUpdate(id)
        .filter(
            signIn ->
                signIn.status() == WebSignInEntity.Status.ASKED
                    && deviceId.equals(signIn.askedBy())
                    && signIn.expiresAt().isAfter(now));
  }

  // PostgreSQL stores microseconds. Truncating first makes responses equal later reads.
  private static Instant now() {
    return Instant.now().truncatedTo(ChronoUnit.MICROS);
  }
}
