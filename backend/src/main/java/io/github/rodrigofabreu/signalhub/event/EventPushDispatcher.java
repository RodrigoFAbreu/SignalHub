package io.github.rodrigofabreu.signalhub.event;

import io.github.rodrigofabreu.signalhub.client.ClientService;
import io.github.rodrigofabreu.signalhub.push.DeliveryResult;
import io.github.rodrigofabreu.signalhub.push.PushDelivery;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.runtime.Startup;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import java.util.ArrayList;
import java.util.EnumMap;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;
import org.jboss.logging.Logger;

/**
 * Pushes every stored event to every client that has a push target and whose push preferences allow
 * it; events a client's preferences exclude are only not pushed to it. Events come from the {@link
 * PushDispatches} outbox, written with the event, so a push is attempted at least once for every
 * acknowledged event even across restarts; clients deduplicate by event ID. A send that fails
 * temporarily is retried with growing delays, up to {@link #MAX_ATTEMPTS} sends in all; other
 * failures are final, as repeating them cannot help.
 */
// Created at startup so its meters are scraped before the first use.
@Startup
@ApplicationScoped
class EventPushDispatcher {

  private static final Logger LOG = Logger.getLogger(EventPushDispatcher.class);

  // Far longer than one dispatch takes (a few sends with 10 s timeouts), so a claim expires only
  // when its dispatcher stopped.
  static final Duration LEASE = Duration.ofMinutes(5);

  // How long to wait after each failed send before the next one: a provider outage of about 40
  // minutes is bridged, and then the push is given up, as it would interrupt too late to matter.
  // The event stays in the inbox either way.
  static final List<Duration> RETRY_DELAYS =
      List.of(
          Duration.ofSeconds(30),
          Duration.ofMinutes(2),
          Duration.ofMinutes(10),
          Duration.ofMinutes(30));
  static final int MAX_ATTEMPTS = RETRY_DELAYS.size() + 1;

  private final PushDispatches dispatches;
  private final EventService events;
  private final ClientService clients;
  private final PushDelivery delivery;
  private final Counter abandoned;
  // Counted by each run, so a scrape reads memory rather than the database.
  private final AtomicLong pendingDispatches = new AtomicLong();
  private final AtomicLong pendingRetries = new AtomicLong();

  EventPushDispatcher(
      PushDispatches dispatches,
      EventService events,
      ClientService clients,
      PushDelivery delivery,
      MeterRegistry registry) {
    this.dispatches = dispatches;
    this.events = events;
    this.clients = clients;
    this.delivery = delivery;
    this.abandoned =
        Counter.builder("signalhub.push.retries.abandoned")
            .description("Pushes to one client given up after the last attempt failed temporarily")
            .register(registry);
    Gauge.builder("signalhub.push.dispatch.pending", pendingDispatches, AtomicLong::get)
        .description("Events whose push is not dispatched yet, as of the last dispatcher run")
        .register(registry);
    Gauge.builder("signalhub.push.retries.pending", pendingRetries, AtomicLong::get)
        .description("Pushes to one client waiting to be sent again, as of the last dispatcher run")
        .register(registry);
  }

  @Scheduled(
      identity = "push-dispatch",
      every = "${signalhub.push.dispatch.interval:2s}",
      concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
  void run() {
    dispatchPending();
  }

  /**
   * Dispatches every pending event, then sends every retry that is due; returns how many events
   * were dispatched.
   */
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
    for (var next = dispatches.claimNextRetry(LEASE);
        next.isPresent();
        next = dispatches.claimNextRetry(LEASE)) {
      try {
        retry(next.get());
      } catch (RuntimeException e) {
        // As above: the claim expires and the retry is sent again.
        LOG.warnf(
            "Push retry of event %s to client %s failed: %s",
            next.get().eventId(), next.get().clientId(), e.getClass().getName());
      }
    }
    var backlog = dispatches.backlog();
    pendingDispatches.set(backlog.dispatches());
    pendingRetries.set(backlog.retries());
    return dispatched;
  }

  private void dispatch(UUID eventId) {
    var push = events.pushFor(eventId);
    var retryClientIds = new ArrayList<UUID>();
    if (push.isPresent()) {
      var results = new EnumMap<DeliveryResult, Integer>(DeliveryResult.class);
      var excluded = 0;
      for (var recipient : clients.pushRecipients()) {
        if (push.get().allowedBy(recipient.preferences())) {
          var result = delivery.deliver(recipient.clientId(), push.get().message());
          results.merge(result, 1, Integer::sum);
          if (result == DeliveryResult.TRANSIENT_FAILURE) {
            retryClientIds.add(recipient.clientId());
          }
        } else {
          excluded++;
        }
      }
      LOG.debugf(
          "Dispatched the push for event %s: %s, %d excluded by preferences",
          eventId, results, excluded);
    }
    dispatches.complete(eventId, retryClientIds, RETRY_DELAYS.get(0));
  }

  /**
   * Sends a push again to one client. The client's push target and preferences are read now, so a
   * client that was revoked, lost its target or muted the event meanwhile is not sent to.
   */
  private void retry(PushRetry retry) {
    var push = events.pushFor(retry.eventId());
    var recipient = clients.pushRecipient(retry.clientId());
    if (push.isPresent()
        && recipient.isPresent()
        && push.get().allowedBy(recipient.get().preferences())) {
      var result = delivery.deliver(retry.clientId(), push.get().message());
      var attempts = retry.attempts() + 1;
      if (result == DeliveryResult.TRANSIENT_FAILURE) {
        if (attempts < MAX_ATTEMPTS) {
          dispatches.retryLater(retry, RETRY_DELAYS.get(attempts - 1));
          return;
        }
        LOG.warnf(
            "Gave up the push of event %s to client %s after %d attempts",
            retry.eventId(), retry.clientId(), attempts);
        abandoned.increment();
      } else {
        LOG.debugf(
            "Retried the push of event %s to client %s: %s (attempt %d)",
            retry.eventId(), retry.clientId(), result, attempts);
      }
    }
    dispatches.completeRetry(retry);
  }
}
