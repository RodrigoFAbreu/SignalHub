"""The Compose stack's images and health.

Old step "Start PostgreSQL and the backend" (the limits), "The images are built
for the runner's architecture", "Liveness, readiness and OpenAPI respond" and
"An image built from source reports a development version".
"""

import os
import unittest

from signalhub_stack import StackTestCase, compose, container, host, inspect, run, text


def image_of(service: str) -> str:
    return inspect(container(service), "{{.Image}}")


class ComposeImages(StackTestCase):
    @unittest.skipUnless(
        os.environ.get("SIGNALHUB_EXPECT_LIMITS"),
        "set SIGNALHUB_EXPECT_LIMITS when the stack runs with the limits of docs/architecture.md#resources",
    )
    def test_the_backend_runs_with_the_recommended_memory_limit(self):
        memory = inspect(container("backend"), "{{.HostConfig.Memory}}")
        self.assertEqual("536870912", memory)

    def test_the_images_are_built_for_the_hosts_architecture(self):
        expected = (
            os.environ.get("SIGNALHUB_EXPECT_ARCH")
            or text(run("docker", "version", "--format", "{{.Server.Arch}}")).strip()
        )
        services = text(compose("config", "--services")).split()
        for service in services:
            with self.subTest(service=service):
                architecture = text(
                    run(
                        "docker",
                        "image",
                        "inspect",
                        "--format",
                        "{{.Architecture}}",
                        image_of(service),
                    )
                ).strip()
                self.assertEqual(expected, architecture)

    def test_liveness_responds(self):
        self.assertStatus(host().get("/q/health/live"), 200)

    def test_readiness_responds(self):
        self.assertStatus(host().get("/q/health/ready"), 200)

    def test_openapi_responds(self):
        self.assertStatus(host().get("/q/openapi"), 200)

    def test_an_image_built_from_source_reports_a_development_version(self):
        # Compose builds from source, not as the release does, so the image is not a release.
        info = self.ok(host().get("/q/info"))
        self.assertEqual({"version": "development"}, info["signalhub"])
        label = text(
            run(
                "docker",
                "image",
                "inspect",
                "--format",
                '{{ index .Config.Labels "org.opencontainers.image.version" }}',
                image_of("backend"),
            )
        ).strip()
        self.assertEqual("development", label)


if __name__ == "__main__":
    unittest.main()
