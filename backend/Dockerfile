# syntax=docker/dockerfile:1

# Production image for the SignalHub backend (Quarkus, JVM mode).
# Build from the repository root with `docker compose build`, or directly with
#   docker build --tag signalhub-backend backend
# Releases publish it as ghcr.io/rodrigofabreu/signalhub:X.Y.Z for linux/amd64 and
# linux/arm64 (docs/development.md#release-process).
# Tests are not run here: they need Docker (Testcontainers) and run in CI.

# Base images are pinned by digest for reproducible builds; Dependabot updates them.
# The build image's Maven version matches .mvn/wrapper/maven-wrapper.properties.
FROM maven:3.9-eclipse-temurin-26-noble@sha256:b2c1ad85954592f9928e84327c65201f308ad9b5d8ed7d5b823717c97bf23fbb AS build
WORKDIR /build
# Resolve dependencies in their own layer so source changes do not re-download them.
COPY pom.xml ./
RUN --mount=type=cache,target=/root/.m2 mvn --batch-mode --quiet quarkus:go-offline
COPY src/ src/
RUN --mount=type=cache,target=/root/.m2 \
  mvn --batch-mode --quiet package -DskipTests -Dspotless.check.skip -Dspotbugs.skip

FROM eclipse-temurin:25-jre-noble@sha256:30772b161c319f9a10c82e30fd77b7b6702c6b051e44e0e9f3d7ab5dd389a5ab
# The health check below uses curl, which the Java 25 JRE image no longer includes.
RUN apt-get update \
  && apt-get install --yes --no-install-recommends curl \
  && rm -rf /var/lib/apt/lists/*
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
