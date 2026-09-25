package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.client.ClientService;
import io.github.rodrigofabreu.signalhub.push.PushDelivery;
import io.github.rodrigofabreu.signalhub.push.PushMessage;
import io.quarkus.runtime.ShutdownEvent;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.event.TransactionPhase;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.RejectedExecutionException;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * Pushes every stored event to every client with a push target. Events wait in the {@code
 * pending_pushes} queue, written with the event, until each recipient was sent the push, so a
 * restart never loses one; a restart mid-dispatch may repeat it, which is why clients deduplicate
 * by event ID. Which events push depends on nothing but generic fields: for now, all of them.
 *
 * <p>A background thread dispatches right after each event commits, at startup, and every minute as
 * a safety net for dispatches that stopped on an error. Sends run outside any transaction.
 */
@ApplicationScoped
class EventPushDispatcher {

  private static final Logger LOG = Logger.getLogger(EventPushDispatcher.class);

  /**
   * Push bodies stay within provider payload limits (FCM: 4 KiB) even with a maximal title and
   * four-byte characters; the client fetches the full event.
   */
  static final int MAX_BODY_LENGTH = 500;

  /** Data key of the event ID, which the client uses to open the event and drop duplicates. */
  static final String EVENT_ID = "eventId";

  private static final int BATCH_SIZE = 50;
  private static final long SWEEP_INTERVAL_SECONDS = 60;

  private final EventService events;
  private final ClientService clients;
  private final PushDelivery delivery;
  private final boolean background;
  private final AtomicBoolean dispatchQueued = new AtomicBoolean();
  private volatile ScheduledExecutorService worker;

  EventPushDispatcher(
      EventService events,
      ClientService clients,
      PushDelivery delivery,
      @ConfigProperty(name = "signalhub.push.dispatch.background", defaultValue = "true")
          boolean background) {
    this.events = events;
    this.clients = clients;
    this.delivery = delivery;
    this.background = background;
  }

  void start(@Observes StartupEvent startup) {
    if (!background) {
      LOG.info("Background push dispatch is off; queued pushes wait");
      return;
    }
    worker =
        Executors.newSingleThreadScheduledExecutor(
            task -> {
              var thread = new Thread(task, "signalhub-push-dispatch");
              thread.setDaemon(true);
              return thread;
            });
    worker.scheduleWithFixedDelay(
        this::requestDispatch, 0, SWEEP_INTERVAL_SECONDS, TimeUnit.SECONDS);
  }

  void stop(@Observes ShutdownEvent shutdown) {
    var current = worker;
    if (current != null) {
      current.shutdownNow();
    }
  }

  // AFTER_SUCCESS: only a committed event is dispatched, and never inside its transaction.
  void onStored(@Observes(during = TransactionPhase.AFTER_SUCCESS) EventStored event) {
    requestDispatch();
  }

  /**
   * Dispatches every queued push, oldest first, and returns how many events it dispatched. Calls
   * run one at a time; an error stops the call and leaves the rest queued for the next one.
   */
  synchronized int dispatchPending() {
    var dispatched = 0;
    while (true) {
      var batch = events.pendingPushes(BATCH_SIZE);
      if (batch.isEmpty()) {
        return dispatched;
      }
      var recipients = clients.pushRecipients();
      for (var pending : batch) {
        var message = toMessage(pending);
        for (var client : recipients) {
          delivery.deliver(client, message);
        }
        if (Thread.currentThread().isInterrupted()) {
          // Stopping: a send may have been cut short, so the event stays queued for the next start.
          return dispatched;
        }
        events.pushDispatched(pending.eventId());
        LOG.debugf("Dispatched event %s to %d clients", pending.eventId(), recipients.size());
        dispatched++;
      }
    }
  }

  static PushMessage toMessage(PendingPush event) {
    return new PushMessage(
        event.title(), truncate(event.message()), Map.of(EVENT_ID, event.eventId().toString()));
  }

  private static String truncate(String text) {
    if (text == null || text.isEmpty()) {
      return null;
    }
    if (text.codePointCount(0, text.length()) <= MAX_BODY_LENGTH) {
      return text;
    }
    var end = text.offsetByCodePoints(0, MAX_BODY_LENGTH - 1);
    return text.substring(0, end) + "…";
  }

  // Coalesces requests: while a dispatch is waiting to start, another request adds nothing.
  private void requestDispatch() {
    var current = worker;
    if (current == null || !dispatchQueued.compareAndSet(false, true)) {
      return;
    }
    try {
      current.execute(
          () -> {
            dispatchQueued.set(false);
            dispatchInBackground();
          });
    } catch (RejectedExecutionException e) {
      // Shutting down: the queue keeps the push for the next start.
      dispatchQueued.set(false);
    }
  }

  private void dispatchInBackground() {
    try {
      dispatchPending();
    } catch (RuntimeException e) {
      LOG.warnf(e, "Push dispatch stopped; retrying within %d seconds", SWEEP_INTERVAL_SECONDS);
    }
  }
}
