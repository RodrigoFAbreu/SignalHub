package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.client.ClientService;
import io.github.rodrigofabreu.signalhub.push.DeliveryResult;
import io.github.rodrigofabreu.signalhub.push.PushDelivery;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import java.util.EnumMap;
import java.util.UUID;
import org.jboss.logging.Logger;

/**
 * Pushes every stored event to every client that has a push target and whose push preferences allow
 * it; events a client's preferences exclude are only not pushed to it. Events come from the {@link
 * PushDispatches} outbox, written with the event, so a push is attempted at least once for every
 * acknowledged event even across restarts; clients deduplicate by event ID. Each client gets one
 * attempt per event: retrying transient failures is roadmap R13.
 */
@ApplicationScoped
class EventPushDispatcher {

  private static final Logger LOG = Logger.getLogger(EventPushDispatcher.class);

  // Far longer than one dispatch takes (a few sends with 10 s timeouts), so a claim expires only
  // when its dispatcher stopped.
  static final Duration LEASE = Duration.ofMinutes(5);

  private final PushDispatches dispatches;
  private final EventService events;
  private final ClientService clients;
  private final PushDelivery delivery;

  EventPushDispatcher(
      PushDispatches dispatches,
      EventService events,
      ClientService clients,
      PushDelivery delivery) {
    this.dispatches = dispatches;
    this.events = events;
    this.clients = clients;
    this.delivery = delivery;
  }

  @Scheduled(
      identity = "push-dispatch",
      every = "${signalhub.push.dispatch.interval:2s}",
      concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
  void run() {
    dispatchPending();
  }

  /** Dispatches every pending event; returns how many were dispatched. */
  int dispatchPending() {
    var dispatched = 0;
    for (var next = dispatches.claimNext(LEASE);
        next.isPresent();
        next = dispatches.claimNext(LEASE)) {
      try {
        dispatch(next.get());
        dispatched++;
      } catch (RuntimeException e) {
        // The claim expires and the event is dispatched again; carry on with the others.
        LOG.warnf("Push dispatch of event %s failed: %s", next.get(), e.getClass().getName());
      }
    }
    return dispatched;
  }

  private void dispatch(UUID eventId) {
    var push = events.pushFor(eventId);
    if (push.isPresent()) {
      var results = new EnumMap<DeliveryResult, Integer>(DeliveryResult.class);
      var excluded = 0;
      for (var recipient : clients.pushRecipients()) {
        if (push.get().allowedBy(recipient.preferences())) {
          results.merge(
              delivery.deliver(recipient.clientId(), push.get().message()), 1, Integer::sum);
        } else {
          excluded++;
        }
      }
      LOG.debugf(
          "Dispatched the push for event %s: %s, %d excluded by preferences",
          eventId, results, excluded);
    }
    dispatches.complete(eventId);
  }
}
