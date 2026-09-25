package io.github.rodrigofabreu.signalhub.producer;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.ElementType.TYPE;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import jakarta.ws.rs.NameBinding;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

/**
 * Requires the operator's admin token ({@code Authorization: Bearer <token>}). Until owner and
 * client authentication exist, the admin token is the owner's credential: it guards producer
 * management and reading the event listing. Without a configured token these endpoints answer 404.
 */
@NameBinding
@Target({TYPE, METHOD})
@Retention(RUNTIME)
public @interface AdminOnly {}
