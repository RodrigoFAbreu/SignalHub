package io.github.rodrigofabreu.signalhub.client;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Every client, oldest first. An object rather than a bare array, so fields such as paging can be
 * added later without breaking the contract.
 */
@Schema(name = "ClientList", description = "Every client, revoked or not, oldest first.")
public record ClientList(
    @Schema(required = true, description = "The clients, oldest first.")
        List<ClientResponse> items) {

  public ClientList {
    items = List.copyOf(items);
  }
}
