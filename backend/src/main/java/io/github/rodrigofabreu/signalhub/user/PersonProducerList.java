package io.github.rodrigofabreu.signalhub.user;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** The producers a user owns, in an object so that fields can be added later. */
@Schema(name = "PersonProducerList", description = "The producers a user owns, by name.")
public record PersonProducerList(
    @Schema(required = true, description = "The producers, by name.") List<PersonProducer> items) {

  public PersonProducerList {
    items = List.copyOf(items);
  }
}
