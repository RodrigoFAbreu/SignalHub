package io.github.rodrigofabreu.signalhub.client;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Body of {@code PUT /api/v1/client/push-target}. */
@Schema(
    name = "PushTargetRequest",
    description =
        "Where pushes for this client go: the push provider and the address it issued to this"
            + " installation. SignalHub stores the token but never interprets it.")
public record PushTargetRequest(
    @Schema(
            description =
                "Name of the push provider that issued the token. Lowercase letters, digits and"
                    + " . _ -, starting with a letter or digit.",
            examples = "fcm")
        @NotNull
        @Size(max = 50)
        @Pattern(regexp = PROVIDER, message = PROVIDER_MESSAGE)
        String provider,
    @Schema(
            description =
                "The provider's address for this installation, such as a registration token."
                    + " Opaque to SignalHub.",
            examples = "dGhpcy1pcy1hbi1leGFtcGxlLXB1c2gtdG9rZW4")
        @NotBlank
        @Size(max = 4096)
        @Pattern(regexp = CreateClientRequest.NO_NUL, message = CreateClientRequest.NO_NUL_MESSAGE)
        String token) {

  static final String PROVIDER = "[a-z0-9][a-z0-9._-]*";
  static final String PROVIDER_MESSAGE =
      "must start with a lowercase letter or digit and contain only lowercase letters, digits and"
          + " . _ -";

  // The token addresses a device; keep it out of logs if this is ever printed.
  @Override
  public String toString() {
    return "PushTargetRequest[provider=" + provider + "]";
  }
}
