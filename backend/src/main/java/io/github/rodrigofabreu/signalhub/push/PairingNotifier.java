package io.github.rodrigofabreu.signalhub.push;

import io.github.rodrigofabreu.signalhub.client.ClientPaired;
import io.github.rodrigofabreu.signalhub.client.ClientService;
import jakarta.annotation.PreDestroy;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.time.Duration;
import java.util.EnumMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import org.jboss.logging.Logger;

/**
 * Tells the owner's devices when a new device pairs, so a pairing code that leaked is noticed at
 * once and its client can be revoked. Every client with a push target and pushes not paused gets
 * it, except the new one. It is a notice, not an event: nothing is stored, nothing appears in the
 * inbox, and it is sent once, without retries; the log keeps the record ("Redeemed pairing ... as
 * client ...").
 */
@ApplicationScoped
public class PairingNotifier {

  private static final Logger LOG = Logger.getLogger(PairingNotifier.class);

  // One thread: notices are rare, and sending them in order keeps them readable.
  private final ExecutorService sender =
      Executors.newSingleThreadExecutor(Thread.ofPlatform().name("pairing-notices").factory());
  private final ClientService clients;
  private final PushDelivery delivery;
  private volatile Future<?> last = CompletableFuture.completedFuture(null);

  PairingNotifier(ClientService clients, PushDelivery delivery) {
    this.clients = clients;
    this.delivery = delivery;
  }

  /**
   * Queues the notice and returns at once: a push provider may take seconds, and the device that
   * just paired is waiting for its key. Never throws, so a notice can never fail a pairing.
   */
  void onPaired(@Observes ClientPaired paired) {
    try {
      last = sender.submit(() -> send(paired));
    } catch (RuntimeException e) {
      LOG.warnf(
          "Could not queue the pairing notice for client %s: %s",
          paired.clientId(), e.getClass().getName());
    }
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

  private void send(ClientPaired paired) {
    try {
      var message = messageFor(paired);
      var results = new EnumMap<DeliveryResult, Integer>(DeliveryResult.class);
      for (var recipient : clients.pushRecipients()) {
        if (!recipient.clientId().equals(paired.clientId()) && recipient.preferences().enabled()) {
          results.merge(delivery.deliver(recipient.clientId(), message), 1, Integer::sum);
        }
      }
      LOG.infof("Sent the pairing notice for client %s: %s", paired.clientId(), results);
    } catch (RuntimeException e) {
      // Nothing waits for the result, so this log line is the only trace of the failure.
      LOG.warnf(
          "Pairing notice for client %s failed: %s", paired.clientId(), e.getClass().getName());
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
