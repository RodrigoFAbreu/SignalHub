package io.github.rodrigofabreu.signalhub.client;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.ElementType.TYPE;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import jakarta.ws.rs.NameBinding;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

/**
 * Requires a valid client key, or the admin token when one is configured. Guards reading events,
 * which every client needs, limited to its user's subscriptions, and the operator may also do with
 * the admin token, seeing every event.
 */
@NameBinding
@Target({TYPE, METHOD})
@Retention(RUNTIME)
public @interface OwnerAuthenticated {}
