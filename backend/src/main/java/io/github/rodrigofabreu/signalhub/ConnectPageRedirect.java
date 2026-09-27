package io.github.rodrigofabreu.signalhub;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.core.Response;
import java.net.URI;
import org.eclipse.microprofile.openapi.annotations.Operation;

/**
 * The Connect page of earlier releases is part of the admin page now; bookmarks and older docs
 * pointing at {@code /connect/} land there. On the backend's own port only, like the page.
 */
@Path("/connect")
public class ConnectPageRedirect {

  static final URI ADMIN_PAGE = URI.create("/admin/");

  @GET
  @Operation(hidden = true)
  public Response redirect() {
    return Response.status(Response.Status.MOVED_PERMANENTLY).location(ADMIN_PAGE).build();
  }
}
