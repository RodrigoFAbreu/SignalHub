package io.github.rodrigofabreu.signalhub.push;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.quarkus.arc.lookup.LookupUnlessProperty;
import jakarta.inject.Inject;
import jakarta.inject.Singleton;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.regex.Pattern;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/**
 * The app's Firebase options for provider {@code fcm}, read from the file {@code
 * SIGNALHUB_PUSH_FCM_CLIENT_OPTIONS_FILE} names: the same JSON object of names and strings the app
 * is built with ({@code client/firebase-options.example.json}). SignalHub serves the values as they
 * are. It only refuses what cannot be client options, above all a service account key, which would
 * let anyone holding a client key send pushes. An unreadable or invalid file stops startup. Error
 * messages name the problem, never a value.
 */
@Singleton
@LookupUnlessProperty(
    name = FcmClientOptions.OPTIONS_FILE,
    stringValue = "",
    lookupIfMissing = false)
final class FcmClientOptions implements PushClientOptions {

  static final String OPTIONS_FILE = "signalhub.push.fcm.client-options-file";

  static final int MAX_OPTIONS = 32;
  static final int MAX_VALUE_LENGTH = 1024;

  private static final Pattern NAME = Pattern.compile("[A-Za-z][A-Za-z0-9_]{0,63}");

  private final Map<String, String> options;

  @Inject
  FcmClientOptions(@ConfigProperty(name = OPTIONS_FILE) Optional<String> optionsFile) {
    this(read(Path.of(optionsFile.orElseThrow())));
  }

  FcmClientOptions(Map<String, String> options) {
    // Served in the file's order.
    this.options = Collections.unmodifiableMap(new LinkedHashMap<>(options));
  }

  @Override
  public String provider() {
    return FcmPushProvider.NAME;
  }

  @Override
  public Map<String, String> options() {
    return options;
  }

  static Map<String, String> read(Path file) {
    try {
      return parse(Files.readString(file, StandardCharsets.UTF_8));
    } catch (IOException e) {
      throw new IllegalStateException(
          "Cannot read the FCM client options file " + file + ": " + e.getClass().getSimpleName(),
          e);
    }
  }

  static Map<String, String> parse(String json) {
    JsonNode root;
    try {
      root = new ObjectMapper().readTree(json);
    } catch (IOException e) {
      // The parser's message may quote the file, which could be a key mistaken for options.
      throw invalid("is not valid JSON");
    }
    if (root == null || !root.isObject()) {
      throw invalid("is not a JSON object");
    }
    if (looksLikeAServiceAccountKey(root)) {
      throw invalid(
          "looks like a service account key. It must hold the app's Firebase options"
              + " (client/firebase-options.example.json); the key goes in"
              + " SIGNALHUB_PUSH_FCM_CREDENTIALS_FILE");
    }
    if (root.isEmpty()) {
      throw invalid("has no options");
    }
    if (root.size() > MAX_OPTIONS) {
      throw invalid("has more than " + MAX_OPTIONS + " options");
    }
    var options = new LinkedHashMap<String, String>();
    for (var entry : root.properties()) {
      var name = entry.getKey();
      var value = entry.getValue();
      if (!NAME.matcher(name).matches()) {
        throw invalid("has an option name that is not letters, digits and underscores");
      }
      if (!value.isTextual()
          || value.asText().isBlank()
          || value.asText().length() > MAX_VALUE_LENGTH) {
        throw invalid(
            "option "
                + name
                + " is not a non-empty string of at most "
                + MAX_VALUE_LENGTH
                + " characters");
      }
      options.put(name, value.asText());
    }
    return options;
  }

  private static boolean looksLikeAServiceAccountKey(JsonNode root) {
    if (root.has("private_key") || "service_account".equals(root.path("type").asText())) {
      return true;
    }
    for (var value : root) {
      if (value.isTextual() && value.asText().contains("PRIVATE KEY")) {
        return true;
      }
    }
    return false;
  }

  private static IllegalStateException invalid(String problem) {
    return new IllegalStateException("The FCM client options file " + problem);
  }
}
