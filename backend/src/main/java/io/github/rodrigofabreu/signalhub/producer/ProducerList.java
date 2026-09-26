package io.github.rodrigofabreu.signalhub.producer;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/**
 * Every producer, by name. An object rather than a bare array, so fields such as paging can be
 * added later without breaking the contract.
 */
@Schema(name = "ProducerList", description = "Every producer and its keys, by name.")
public record ProducerList(
    @Schema(required = true, description = "The producers, by name.")
        List<ProducerResponse> items) {

  public ProducerList {
    items = List.copyOf(items);
  }
}
