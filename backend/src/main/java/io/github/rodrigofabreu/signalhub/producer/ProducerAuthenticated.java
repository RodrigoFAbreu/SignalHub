package io.github.rodrigofabreu.signalhub.producer;

import static java.lang.annotation.ElementType.METHOD;
import static java.lang.annotation.ElementType.TYPE;
import static java.lang.annotation.RetentionPolicy.RUNTIME;

import jakarta.ws.rs.NameBinding;
import java.lang.annotation.Retention;
import java.lang.annotation.Target;

/**
 * Requires a valid producer API key ({@code Authorization: Bearer <key>}) before the endpoint runs,
 * and makes the producer available through {@link AuthenticatedProducer}.
 */
@NameBinding
@Target({TYPE, METHOD})
@Retention(RUNTIME)
public @interface ProducerAuthenticated {}
