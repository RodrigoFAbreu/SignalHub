package io.github.rodrigofabreu.signalhub.push;

import io.github.rodrigofabreu.signalhub.client.ClientService;
import jakarta.enterprise.context.ApplicationScoped;
import java.util.UUID;
import org.jboss.logging.Logger;

/**
 * Pushes a message to one client through the provider its push target names. This is what the rest
 * of SignalHub calls to deliver a push; it never sees a concrete provider. Sends run outside any
 * database transaction. It sends once; the result says whether a retry could help, and the caller
 * decides whether to retry.
 */
@ApplicationScoped
public class PushDelivery {

  private static final Logger LOG = Logger.getLogger(PushDelivery.class);

  private final ClientService clients;
  private final PushProviders providers;

  PushDelivery(ClientService clients, PushProviders providers) {
    this.clients = clients;
    this.providers = providers;
  }

  public DeliveryResult deliver(UUID clientId, PushMessage message) {
    var target = clients.pushTargetOf(clientId);
    if (target.isEmpty()) {
      return DeliveryResult.NO_TARGET;
    }
    var address = target.get();
    var provider = providers.named(address.provider());
    if (provider.isEmpty()) {
      LOG.debugf("No push provider %s for client %s", address.provider(), clientId);
      return DeliveryResult.UNSUPPORTED_PROVIDER;
    }
    var outcome = send(provider.get(), address.token(), message, clientId);
    return switch (outcome.status()) {
      case DELIVERED -> DeliveryResult.DELIVERED;
      case INVALID_TARGET -> {
        // Only if the client still has this target: it may have registered a new one meanwhile.
        if (clients.dropPushTarget(clientId, address)) {
          LOG.infof(
              "Removed the push target of client %s: %s rejected it (%s)",
              clientId, address.provider(), outcome.detail());
        }
        yield DeliveryResult.INVALID_TARGET;
      }
      case TRANSIENT_FAILURE -> {
        LOG.warnf(
            "Push to client %s via %s failed temporarily: %s",
            clientId, address.provider(), outcome.detail());
        yield DeliveryResult.TRANSIENT_FAILURE;
      }
      case PERMANENT_FAILURE -> {
        LOG.warnf(
            "Push to client %s via %s failed: %s", clientId, address.provider(), outcome.detail());
        yield DeliveryResult.PERMANENT_FAILURE;
      }
    };
  }

  private static PushOutcome send(
      PushProvider provider, String token, PushMessage message, UUID clientId) {
    try {
      return provider.send(token, message);
    } catch (RuntimeException e) {
      // The exception message could quote the token, so only its type is logged.
      LOG.warnf(
          "Push provider %s threw %s for client %s",
          provider.name(), e.getClass().getName(), clientId);
      return new PushOutcome(PushOutcome.Status.TRANSIENT_FAILURE, e.getClass().getSimpleName());
    }
  }
}
