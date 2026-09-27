package io.github.rodrigofabreu.signalhub.client;

import io.quarkus.runtime.Startup;
import jakarta.enterprise.context.ApplicationScoped;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Builds pairing URIs, {@code signalhub://pair?server=<public URL>&code=<code>}, from the address
 * devices reach the server at ({@code SIGNALHUB_PUBLIC_URL}). The server cannot learn that address
 * from a request: the operator calls the management API on the host, not through the proxy. Without
 * it, pairings have no URI and the device is given the address and code separately.
 */
// Created at startup so a malformed public URL stops the service instead of the first pairing.
@Startup
@ApplicationScoped
class PairingUris {

  static final String SCHEME = "signalhub";

  private final Optional<String> publicUrl;

  PairingUris(@ConfigProperty(name = "signalhub.public-url") Optional<String> publicUrl) {
    this.publicUrl = publicUrl.filter(url -> !url.isBlank()).map(PairingUris::serverAddress);
  }

  /** The pairing URI for this code, or empty if no public URL is configured. */
  Optional<String> of(String code) {
    return publicUrl.map(
        server ->
            SCHEME
                + "://pair?server="
                + URLEncoder.encode(server, StandardCharsets.UTF_8)
                + "&code="
                + code);
  }

  /**
   * The public URL as devices use it, without a trailing slash. Throws unless it is an absolute
   * {@code http} or {@code https} URL with a host and without credentials, query or fragment.
   */
  static String serverAddress(String publicUrl) {
    URI uri;
    try {
      uri = new URI(publicUrl.strip());
    } catch (URISyntaxException e) {
      throw invalid();
    }
    var scheme = uri.getScheme();
    if (!("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))
        || uri.getHost() == null
        || uri.getRawUserInfo() != null
        || uri.getRawQuery() != null
        || uri.getRawFragment() != null) {
      throw invalid();
    }
    return uri.toString().replaceFirst("/+$", "");
  }

  private static IllegalStateException invalid() {
    return new IllegalStateException(
        "SIGNALHUB_PUBLIC_URL must be the address devices reach SignalHub at, such as"
            + " https://signalhub.example.com, without credentials, query or fragment;"
            + " leave it unset for pairings without a URI");
  }
}
