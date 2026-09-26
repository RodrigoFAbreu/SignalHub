package io.github.rodrigofabreu.signalhub;

import io.quarkus.info.runtime.spi.InfoContributor;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * Which SignalHub release a running backend is, and the commit it was built from. The release
 * workflow bakes both into the image it publishes (SIGNALHUB_VERSION and SIGNALHUB_REVISION, see
 * backend/Dockerfile); any other build has neither and calls itself a development build, so it can
 * never pass for a release. Shown at /q/info under {@code signalhub} and in the startup summary.
 */
@ApplicationScoped
public class BuildInfo implements InfoContributor {

  static final String DEVELOPMENT = "development";

  private final Optional<String> version;
  private final Optional<String> revision;

  @Inject
  BuildInfo(
      @ConfigProperty(name = "signalhub.version") Optional<String> version,
      @ConfigProperty(name = "signalhub.revision") Optional<String> revision) {
    this.version = version.map(String::strip).filter(value -> !value.isEmpty());
    this.revision = revision.map(String::strip).filter(value -> !value.isEmpty());
  }

  /** The release version without {@code v}, such as {@code 1.2.3}, or {@code development}. */
  public String version() {
    return version.orElse(DEVELOPMENT);
  }

  /** The full commit hash the build was made from, when the build recorded one. */
  public Optional<String> revision() {
    return revision;
  }

  /** One phrase for logs: {@code SignalHub 1.2.3 (commit ...)} or a development build. */
  public String describe() {
    var name = version.map(release -> "SignalHub " + release).orElse("SignalHub development build");
    return name + revision.map(commit -> " (commit " + commit + ")").orElse("");
  }

  @Override
  public String name() {
    return "signalhub";
  }

  @Override
  public Map<String, Object> data() {
    var data = new LinkedHashMap<String, Object>();
    data.put("version", version());
    revision.ifPresent(commit -> data.put("revision", commit));
    return data;
  }
}
