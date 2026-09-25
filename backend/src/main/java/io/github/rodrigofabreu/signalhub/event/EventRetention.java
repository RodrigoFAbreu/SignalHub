package io.github.rodrigofabreu.signalhub.event;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.quarkus.runtime.Startup;
import io.quarkus.scheduler.Scheduled;
import jakarta.annotation.PostConstruct;
import jakarta.enterprise.context.ApplicationScoped;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import org.jboss.logging.Logger;

/**
 * Deletes events older than the operator's retention period ({@code SIGNALHUB_EVENTS_RETENTION}),
 * so storage stops growing with the history. Without one, events are kept forever. Age is measured
 * from {@code createdAt}, the server's clock; read state does not matter. An event's pending push
 * and retries go with it.
 */
// Created at startup so a bad retention period stops the service and the meter is scraped early.
@Startup
@ApplicationScoped
class EventRetention {

  private static final Logger LOG = Logger.getLogger(EventRetention.class);

  // Shorter periods would delete events before the owner has seen them or their pushes have been
  // retried; a mistyped unit (1h for 1d) is caught rather than emptying the inbox.
  static final Duration MINIMUM = Duration.ofDays(1);

  // Deleted per transaction, so pruning a large backlog never holds long locks or a huge undo.
  static final int BATCH_SIZE = 1000;

  private final Optional<Duration> retention;
  private final EventService events;
  private final Counter deleted;

  EventRetention(
      @ConfigProperty(name = "signalhub.events.retention") Optional<Duration> retention,
      EventService events,
      MeterRegistry registry) {
    this.retention = retention;
    this.events = events;
    this.deleted =
        Counter.builder("signalhub.events.deleted")
            .description("Events deleted because they were older than the retention period")
            .register(registry);
  }

  @PostConstruct
  void checkRetention() {
    check(retention);
  }

  static void check(Optional<Duration> retention) {
    if (retention.isPresent() && retention.get().compareTo(MINIMUM) < 0) {
      throw new IllegalStateException(
          "SIGNALHUB_EVENTS_RETENTION must be at least 1d (one day), for example 365d;"
              + " leave it unset to keep events forever");
    }
  }

  @Scheduled(
      identity = "event-retention",
      every = "1h",
      delayed = "1m",
      concurrentExecution = Scheduled.ConcurrentExecution.SKIP)
  void run() {
    deleteExpired(Instant.now());
  }

  /**
   * Deletes every event created before {@code now} minus the retention period; returns how many.
   */
  int deleteExpired(Instant now) {
    if (retention.isEmpty()) {
      return 0;
    }
    var cutoff = now.minus(retention.get());
    var total = 0;
    int batch;
    do {
      batch = events.deleteCreatedBefore(cutoff, BATCH_SIZE);
      total += batch;
      deleted.increment(batch);
    } while (batch == BATCH_SIZE);
    if (total > 0) {
      LOG.infof(
          "Deleted %d events older than the retention period (created before %s)", total, cutoff);
    }
    return total;
  }
}
