package io.github.rodrigofabreu.signalhub.push;

import io.quarkus.runtime.Startup;
import jakarta.enterprise.inject.Any;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.util.List;
import java.util.Optional;
import org.jboss.logging.Logger;

/**
 * The push client options this server gives its clients, if any. Checked at startup: options for a
 * provider SignalHub cannot send through, or for two providers, stop the service, since an app
 * would register a push target that never receives anything.
 */
@Startup
@Singleton
public final class PushClientConfig {

  private static final Logger LOG = Logger.getLogger(PushClientConfig.class);

  private final Optional<PushClientOptions> current;

  @Inject
  PushClientConfig(PushProviders providers, @Any Instance<PushClientOptions> options) {
    this(providers, options.stream().toList());
  }

  PushClientConfig(PushProviders providers, List<PushClientOptions> options) {
    if (options.size() > 1) {
      throw new IllegalStateException("Push client options are set for more than one provider");
    }
    current = options.stream().findFirst();
    current.ifPresent(
        served -> {
          if (providers.named(served.provider()).isEmpty()) {
            throw new IllegalStateException(
                "Push client options are set for provider "
                    + served.provider()
                    + ", which is not enabled");
          }
        });
    LOG.infof(
        "Push client options: %s",
        current.map(served -> "served for " + served.provider()).orElse("none"));
  }

  /** The options clients get, empty if the operator set none. */
  public Optional<PushClientOptions> current() {
    return current;
  }
}
