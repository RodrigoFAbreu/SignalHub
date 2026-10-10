package io.github.rodrigofabreu.signalhub.producer;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** The producers a user owns, by name, in an object so that fields can be added later. */
@Schema(name = "OwnProducerList", description = "The producers the caller owns, by name.")
public record OwnProducerList(
    @Schema(required = true, description = "The producers, by name.")
        List<OwnProducerResponse> items) {

  public OwnProducerList {
    items = List.copyOf(items);
  }
}
