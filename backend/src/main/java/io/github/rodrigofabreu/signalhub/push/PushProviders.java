package io.github.rodrigofabreu.signalhub.push;

import static java.util.stream.Collectors.toUnmodifiableMap;

import io.quarkus.runtime.Startup;
import jakarta.enterprise.inject.Any;
import jakarta.enterprise.inject.Instance;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.regex.Pattern;
import org.jboss.logging.Logger;

/**
 * The active push providers by name. Checked at startup: two providers with one name, or a name
 * that no push target could carry, stop the service instead of misrouting pushes.
 */
@Startup
@Singleton
final class PushProviders {

  private static final Logger LOG = Logger.getLogger(PushProviders.class);

  // Same rule as the provider of a push target (see PushTargetRequest).
  private static final Pattern NAME = Pattern.compile("[a-z0-9][a-z0-9._-]{0,49}");

  private final Map<String, PushProvider> byName;

  @Inject
  PushProviders(@Any Instance<PushProvider> providers) {
    this(providers.stream().toList());
  }

  PushProviders(List<PushProvider> providers) {
    for (var provider : providers) {
      if (!NAME.matcher(provider.name()).matches()) {
        throw new IllegalStateException("Invalid push provider name: " + provider.name());
      }
    }
    try {
      byName =
          providers.stream().collect(toUnmodifiableMap(PushProvider::name, Function.identity()));
    } catch (IllegalStateException e) {
      throw new IllegalStateException("Two push providers share a name", e);
    }
    LOG.infof("Push providers: %s", byName.isEmpty() ? "none" : byName.keySet());
  }

  Optional<PushProvider> named(String name) {
    return Optional.ofNullable(byName.get(name));
  }
}
