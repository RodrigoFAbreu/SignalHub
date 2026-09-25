package io.github.rodrigofabreu.signalhub.api;

import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.cfg.CoercionAction;
import com.fasterxml.jackson.databind.cfg.CoercionInputShape;
import com.fasterxml.jackson.databind.type.LogicalType;
import io.quarkus.jackson.ObjectMapperCustomizer;
import jakarta.inject.Singleton;

/**
 * Request bodies are public contracts, so JSON is read strictly: a value must have the documented
 * JSON type instead of being coerced into it. Loosening this later is compatible; tightening it
 * would break producers.
 */
@Singleton
class StrictJson implements ObjectMapperCustomizer {

  @Override
  public void customize(ObjectMapper mapper) {
    mapper.enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
    mapper.enable(DeserializationFeature.FAIL_ON_NUMBERS_FOR_ENUMS);
    // Keeps decimal numbers in producer metadata exact instead of rounding them to doubles.
    mapper.enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS);
    for (var type : new LogicalType[] {LogicalType.Textual, LogicalType.Enum}) {
      mapper
          .coercionConfigFor(type)
          .setCoercion(CoercionInputShape.Integer, CoercionAction.Fail)
          .setCoercion(CoercionInputShape.Float, CoercionAction.Fail)
          .setCoercion(CoercionInputShape.Boolean, CoercionAction.Fail);
    }
  }
}
