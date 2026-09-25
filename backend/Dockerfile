# syntax=docker/dockerfile:1

# Production image for the SignalHub backend (Quarkus, JVM mode).
# Build from the repository root with `docker compose build`, or directly with
#   docker build --tag signalhub-backend backend
# Tests are not run here: they need Docker (Testcontainers) and run in CI.

# Base images are pinned by digest for reproducible builds; Dependabot updates them.
# The build image's Maven version matches .mvn/wrapper/maven-wrapper.properties.
FROM maven:3-eclipse-temurin-26-noble@sha256:c30718f442eb39c55b2d45440bb849d8755ad8d9d6ef67aadefcce150267116f AS build
WORKDIR /build
# Resolve dependencies in their own layer so source changes do not re-download them.
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 mvn --batch-mode --quiet quarkus:go-offline
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 \
  mvn --batch-mode --quiet package -DskipTests -Dspotless.check.skip -Dspotbugs.skip

FROM eclipse-temurin:21-jre-noble@sha256:7739f0ffce786528961eea6bf46d9610ee968ac6127c9b2e93494757bdecce9f
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin signalhub
WORKDIR /app
# Quarkus fast-jar layout: dependencies first, since they change least often.
COPY --from=build /build/target/quarkus-app/lib/ lib/
COPY --from=build /build/target/quarkus-app/quarkus/ quarkus/
COPY --from=build /build/target/quarkus-app/app/ app/
COPY --from=build /build/target/quarkus-app/quarkus-run.jar ./
USER signalhub
EXPOSE 8080
# Size the heap from the container memory limit instead of the JVM's 25% default.
# The log manager must be set before the JVM starts so early JUL logs go through Quarkus.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -Djava.util.logging.manager=org.jboss.logmanager.LogManager"
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail --silent --output /dev/null http://localhost:8080/q/health/ready || exit 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar quarkus-run.jar"]
