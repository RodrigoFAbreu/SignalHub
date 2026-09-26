# syntax=docker/dockerfile:1

# Production image for the SignalHub backend (Quarkus, JVM mode).
# Build from the repository root with `docker compose build`, or directly with
#   docker build --tag signalhub-backend backend
# Releases publish it as ghcr.io/rodrigofabreu/signalhub:X.Y.Z for linux/amd64 and
# linux/arm64 (docs/development.md#release-process).
# Tests are not run here: they need Docker (Testcontainers) and run in CI.

# Base images are pinned by digest for reproducible builds; Dependabot updates them.
# The build image's Maven version matches .mvn/wrapper/maven-wrapper.properties.
FROM maven:3.9.16-eclipse-temurin-21-noble@sha256:c2a2c58516d160f43b50f12baa427ca86989e0bc942609e04aff61da5d9a7d74 AS build
WORKDIR /build
# Resolve dependencies in their own layer so source changes do not re-download them.
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 mvn --batch-mode --quiet quarkus:go-offline
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 \
  mvn --batch-mode --quiet package -DskipTests -Dspotless.check.skip -Dspotbugs.skip

FROM eclipse-temurin:24-jre-noble@sha256:b416d02335e702b0403ff280de9475a3348e29382285969c9d4e17862ce632e7
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
# The release that built the image (docs/development.md#release-process) sets these;
# any other build leaves them empty and so reports itself as a development build, in
# its labels, at /q/info and in the startup summary.
ARG SIGNALHUB_VERSION=
ARG SIGNALHUB_REVISION=
ARG SIGNALHUB_CREATED=
LABEL org.opencontainers.image.title="SignalHub backend" \
  org.opencontainers.image.source="https://github.com/RodrigoFAbreu/SignalHub" \
  org.opencontainers.image.version="${SIGNALHUB_VERSION:-development}" \
  org.opencontainers.image.revision="${SIGNALHUB_REVISION}" \
  org.opencontainers.image.created="${SIGNALHUB_CREATED}"
ENV SIGNALHUB_VERSION="${SIGNALHUB_VERSION}" SIGNALHUB_REVISION="${SIGNALHUB_REVISION}"
HEALTHCHECK --interval=10s --timeout=3s --start-period=30s --retries=3 \
  CMD curl --fail --silent --output /dev/null http://localhost:8080/q/health/ready || exit 1
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar quarkus-run.jar"]
