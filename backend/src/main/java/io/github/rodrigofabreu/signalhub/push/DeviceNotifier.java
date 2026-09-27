package io.github.rodrigofabreu.signalhub.push;

import io.github.rodrigofabreu.signalhub.client.ClientChangedByDevice;
import io.github.rodrigofabreu.signalhub.client.ClientPaired;
import io.github.rodrigofabreu.signalhub.client.ClientService;
import jakarta.annotation.PreDestroy;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.time.Duration;
import java.util.EnumMap;
import java.util.Map;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;
import org.jboss.logging.Logger;

/**
 * Tells the owner's devices when a new device pairs, or when an admin device makes another device
 * an admin or revokes one, so a pairing code that leaked or an admin key that was stolen is noticed
 * at once. Every client with a push target and pushes not paused gets it, except a device that just
 * paired. It is a notice, not an event: nothing is stored, nothing appears in the inbox, and it is
 * sent once, without retries; the log keeps the record ("Redeemed pairing ... as client ...",
 * "Client ... revoked client ...").
 */
@ApplicationScoped
public class DeviceNotifier {

  private static final Logger LOG = Logger.getLogger(DeviceNotifier.class);

  // One thread: notices are rare, and sending them in order keeps them readable.
  private final ExecutorService sender =
      Executors.newSingleThreadExecutor(Thread.ofPlatform().name("device-notices").factory());
  private final ClientService clients;
  private final PushDelivery delivery;
  private volatile Future<?> last = CompletableFuture.completedFuture(null);

  DeviceNotifier(ClientService clients, PushDelivery delivery) {
    this.clients = clients;
    this.delivery = delivery;
  }

  /**
   * Queues the notice and returns at once: a push provider may take seconds, and the device that
   * just paired is waiting for its key. Never throws, so a notice can never fail a pairing.
   */
  void onPaired(@Observes ClientPaired paired) {
    queue("pairing notice", paired.clientId(), () -> messageFor(paired), paired.clientId());
  }

  /**
   * Queues the notice and returns at once. Never throws, so a notice can never fail the change.
   * Every device is told, the one that made the change included: its key may be in someone else's
   * hands.
   */
  void onChangedByDevice(@Observes ClientChangedByDevice changed) {
    queue("device-change notice", changed.clientId(), () -> messageFor(changed), null);
  }

  static PushMessage messageFor(ClientPaired paired) {
    // An admin device is said to be one: it matters most if the code leaked.
    return new PushMessage(
        paired.admin() ? "New admin device paired" : "New device paired",
        "\""
            + paired.name()
            + (paired.admin()
                ? "\" is an admin device and can now read your SignalHub events."
                : "\" can now read your SignalHub events.")
            + " If you did not pair it, revoke it.",
        Map.of("notice", "client-paired", "clientId", paired.clientId().toString()));
  }

  static PushMessage messageFor(ClientChangedByDevice changed) {
    var by = "\"" + changed.byName() + "\"";
    var client = "\"" + changed.name() + "\"";
    // Recovering from a stolen admin key needs the admin token, so the notice points there.
    return switch (changed.change()) {
      case MADE_ADMIN ->
          new PushMessage(
              "Device made an admin",
              by
                  + " made "
                  + client
                  + " an admin device. If this was not you, revoke both on the admin page.",
              data("client-made-admin", changed));
      case REVOKED ->
          new PushMessage(
              "Device revoked",
              by
                  + " revoked "
                  + client
                  + ". If this was not you, revoke "
                  + by
                  + " on the admin page.",
              data("client-revoked", changed));
    };
  }

  private static Map<String, String> data(String notice, ClientChangedByDevice changed) {
    return Map.of(
        "notice",
        notice,
        "clientId",
        changed.clientId().toString(),
        "byClientId",
        changed.byClientId().toString());
  }

  private void queue(String what, UUID clientId, Supplier<PushMessage> message, UUID skipped) {
    try {
      last = sender.submit(() -> send(what, clientId, message, skipped));
    } catch (RuntimeException e) {
      LOG.warnf("Could not queue the %s for client %s: %s", what, clientId, e.getClass().getName());
    }
  }

  private void send(String what, UUID clientId, Supplier<PushMessage> notice, UUID skipped) {
    try {
      var message = notice.get();
      var results = new EnumMap<DeliveryResult, Integer>(DeliveryResult.class);
      for (var recipient : clients.pushRecipients()) {
        if (!recipient.clientId().equals(skipped) && recipient.preferences().enabled()) {
          results.merge(delivery.deliver(recipient.clientId(), message), 1, Integer::sum);
        }
      }
      LOG.infof("Sent the %s for client %s: %s", what, clientId, results);
    } catch (RuntimeException e) {
      // Nothing waits for the result, so this log line is the only trace of the failure.
      LOG.warnf("The %s for client %s failed: %s", what, clientId, e.getClass().getName());
    }
  }

  /** Waits until every notice queued so far is sent; for tests. */
  public void awaitSent(Duration timeout) throws Exception {
    last.get(timeout.toMillis(), TimeUnit.MILLISECONDS);
  }

  @PreDestroy
  void stop() {
    sender.shutdown();
  }
}
