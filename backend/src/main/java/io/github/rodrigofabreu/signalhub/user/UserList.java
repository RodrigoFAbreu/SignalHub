package io.github.rodrigofabreu.signalhub.user;

import java.util.List;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

/** Every user, oldest first, in an object so that fields can be added later. */
@Schema(name = "UserList", description = "Every user, revoked or not, oldest first.")
public record UserList(
    @Schema(required = true, description = "The users, oldest first.") List<UserResponse> items) {

  public UserList {
    items = List.copyOf(items);
  }
}
