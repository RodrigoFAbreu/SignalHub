package io.github.rodrigofabreu.signalhub.user;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** The users on the server with their details, for an admin's device. */
@Schema(
    name = "DetailedUserList",
    description = "The users of this server who are not revoked, by name, ignoring case.")
public record DetailedUserList(
    @Schema(required = true, description = "The users, by name.") List<DetailedUser> items) {

  public DetailedUserList {
    items = List.copyOf(items);
  }
}
