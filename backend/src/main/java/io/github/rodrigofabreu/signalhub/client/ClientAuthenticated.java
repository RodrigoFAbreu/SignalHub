package io.github.rodrigofabreu.signalhub.client;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.ElementType.TYPE;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import jakarta.ws.rs.NameBinding;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

/**
 * Requires a valid client key ({@code Authorization: Bearer <key>}) before the endpoint runs, and
 * makes the client available through {@link AuthenticatedClient}.
 */
@NameBinding
@Target({TYPE, METHOD})
@Retention(RUNTIME)
public @interface ClientAuthenticated {}
