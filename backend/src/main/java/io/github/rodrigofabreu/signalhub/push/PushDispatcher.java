package io.github.rodrigofabreu.signalhub.push;

import io.github.rodrigofabreu.signalhub.client.ClientService;
import io.github.rodrigofabreu.signalhub.client.PushTarget;
import io.quarkus.runtime.Startup;
import jakarta.annotation.PreDestroy;
import jakarta.enterprise.event.Observes;
import jakarta.enterprise.event.TransactionPhase;
import jakarta.enterprise.inject.Any;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Singleton;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.regex.Pattern;
import org.jboss.logging.Logger;

/**
 * Sends a push about each stored event to every client with a push target, through the provider the
 * target names. Core code requests delivery by firing a {@link PushMessage}; it never sees a
 * provider.
 *
 * <p>Delivery starts only after the event's transaction commits, so a push never announces an event
 * that was rolled back, and runs on one background thread, so a slow provider never delays the
 * producer's response. Failures are logged and not retried, and pushes still queued when the
 * service stops are lost; the event itself is durable either way.
 */
@Startup
@Singleton
public final class PushDispatcher {

  private static final Logger LOG = Logger.getLogger(PushDispatcher.class);
  private static final Pattern PROVIDER_NAME = Pattern.compile("[a-z0-9][a-z0-9._-]{0,49}");

  private final Map<String, PushProvider> providers;
  private final ClientService clients;
  // One thread: pushes go out in event order, and provider calls never compete with each other.
  private final ExecutorService executor =
      Executors.newSingleThreadExecutor(task -> new Thread(task, "signalhub-push"));

  PushDispatcher(@Any Instance<PushProvider> providers, ClientService clients) {
    this.providers = byName(providers);
    this.clients = clients;
    LOG.infof(
        "Push providers: %s",
        this.providers.isEmpty() ? "none (push targets are stored, nothing is sent)" : names());
  }

  /** Indexes providers by name, refusing to start with an invalid or duplicate name. */
  static Map<String, PushProvider> byName(Iterable<PushProvider> providers) {
    var byName = new TreeMap<String, PushProvider>();
    for (var provider : providers) {
      var name = provider.name();
      if (name == null || !PROVIDER_NAME.matcher(name).matches()) {
        throw new IllegalStateException("Invalid push provider name: " + name);
      }
      if (byName.putIfAbsent(name, provider) != null) {
        throw new IllegalStateException("Two push providers are named " + name);
      }
    }
    return Map.copyOf(byName);
  }

  void onEventStored(@Observes(during = TransactionPhase.AFTER_SUCCESS) PushMessage message) {
    executor.execute(
        () -> {
          try {
            deliver(message);
          } catch (RuntimeException e) {
            // For example, the database is unavailable. The event is stored; only its push is lost.
            LOG.errorf(e, "Push of event %s failed", message.eventId());
          }
        });
  }

  /**
   * Sends the message to every current push target, one at a time. A target whose provider is not
   * available is skipped; a failure at one target does not affect the others.
   */
  void deliver(PushMessage message) {
    for (var target : clients.pushTargets()) {
      var provider = providers.get(target.provider());
      if (provider == null) {
        LOG.debugf(
            "No push to client %s for event %s: provider %s is not available",
            target.clientId(), message.eventId(), target.provider());
        continue;
      }
      handle(target, message, send(provider, target, message));
    }
  }

  private static PushResult send(PushProvider provider, PushTarget target, PushMessage message) {
    try {
      var result = provider.send(message, target.token());
      return result == null ? PushResult.FAILED : result;
    } catch (RuntimeException e) {
      // The exception is not logged: provider exceptions may quote the request, token included.
      LOG.warnf(
          "Push provider %s threw %s for client %s",
          target.provider(), e.getClass().getName(), target.clientId());
      return PushResult.FAILED;
    }
  }

  private void handle(PushTarget target, PushMessage message, PushResult result) {
    switch (result) {
      case DELIVERED ->
          LOG.debugf("Pushed event %s to client %s", message.eventId(), target.clientId());
      case INVALID_TARGET -> {
        LOG.infof(
            "Provider %s rejected the push target of client %s as invalid",
            target.provider(), target.clientId());
        try {
          clients.dropPushTarget(target);
        } catch (RuntimeException e) {
          LOG.errorf(e, "Could not remove the push target of client %s", target.clientId());
        }
      }
      case FAILED ->
          LOG.warnf(
              "Push of event %s to client %s via %s failed",
              message.eventId(), target.clientId(), target.provider());
    }
  }

  private String names() {
    return String.join(", ", providers.keySet());
  }

  @PreDestroy
  void stop() {
    executor.shutdownNow();
  }
}
