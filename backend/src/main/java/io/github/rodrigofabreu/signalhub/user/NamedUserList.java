package io.github.rodrigofabreu.signalhub.user;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** The users on the server, by name, in an object so that fields can be added later. */
@Schema(
    name = "NamedUserList",
    description = "The users of this server who are not revoked, by name, ignoring case.")
public record NamedUserList(
    @Schema(required = true, description = "The users, by name.") List<NamedUser> items) {

  public NamedUserList {
    items = List.copyOf(items);
  }
}
