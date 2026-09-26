"""Tests of deployment_files.py against the repository's own files."""

import contextlib
import io
import tarfile
import tempfile
import unittest
from pathlib import Path

import deployment_files
from deployment_files import DeploymentFilesError, pack, release_compose

ROOT = Path(__file__).resolve().parents[2]
IMAGE = "ghcr.io/rodrigofabreu/signalhub:1.2.3@sha256:" + "0" * 64


def members(path: Path) -> dict[str, tarfile.TarInfo]:
    with tarfile.open(path) as archive:
        return {info.name: info for info in archive.getmembers()}


def read(path: Path, name: str) -> str:
    with tarfile.open(path) as archive:
        return archive.extractfile(name).read().decode()


class ReleaseComposeTest(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "compose.yaml").read_text()

    def test_runs_the_image_instead_of_building(self):
        compose = release_compose(self.source, IMAGE, "1.2.3")
        self.assertIn(
            f"    # SignalHub 1.2.3's published backend image.\n    image: {IMAGE}\n",
            compose,
        )
        self.assertNotIn("build:", compose)
        self.assertNotIn("signalhub-backend:local", compose)

    def test_changes_nothing_else(self):
        compose = release_compose(self.source, IMAGE, "1.2.3")
        removed = set(self.source.splitlines()) - set(compose.splitlines())
        added = set(compose.splitlines()) - set(self.source.splitlines())
        self.assertEqual(len(removed), 4)
        self.assertEqual(
            added,
            {"    # SignalHub 1.2.3's published backend image.", f"    image: {IMAGE}"},
        )

    def test_refuses_a_compose_file_that_builds_differently(self):
        changed = self.source.replace("build: ./backend", "build: ./other")
        with self.assertRaises(DeploymentFilesError):
            release_compose(changed, IMAGE, "1.2.3")

    def test_refuses_what_is_not_an_image_reference(self):
        for image in [
            "",
            "Ghcr.io/x:1",
            "x:1\n    build: .",
            "x:1 # comment",
            "x:${VAR}",
        ]:
            with self.subTest(image=image), self.assertRaises(DeploymentFilesError):
                release_compose(self.source, image, "1.2.3")


class PackTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)

    def test_archive_holds_the_deployment_files(self):
        path = pack(IMAGE, "1.2.3", self.directory)
        self.assertEqual(path, self.directory / "signalhub-1.2.3-deployment.tar.gz")
        self.assertEqual(
            set(members(path)), {"compose.yaml", ".env.example", "proxy/Caddyfile"}
        )
        for info in members(path).values():
            self.assertTrue(info.isfile())
            self.assertEqual(info.mode, 0o644)
        self.assertEqual(
            read(path, ".env.example"), (ROOT / ".env.example").read_text()
        )
        self.assertEqual(
            read(path, "proxy/Caddyfile"), (ROOT / "proxy/Caddyfile").read_text()
        )
        self.assertIn(f"image: {IMAGE}\n", read(path, "compose.yaml"))

    def test_same_contents_same_archive(self):
        first = pack(IMAGE, "1.2.3", self.directory).read_bytes()
        second = pack(IMAGE, "1.2.3", self.directory).read_bytes()
        self.assertEqual(first, second)

    def test_refuses_what_is_not_a_version(self):
        for version in ["", "../1.2.3", "1.2.3/x"]:
            with self.subTest(version=version), self.assertRaises(DeploymentFilesError):
                pack(IMAGE, version, self.directory)


class MainTest(unittest.TestCase):
    def test_prints_the_archive(self):
        with (
            tempfile.TemporaryDirectory() as directory,
            contextlib.redirect_stdout(io.StringIO()) as out,
        ):
            self.assertEqual(deployment_files.main([IMAGE, "1.2.3", directory]), 0)
            self.assertEqual(
                out.getvalue(), f"{directory}/signalhub-1.2.3-deployment.tar.gz\n"
            )

    def test_usage_and_errors(self):
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(deployment_files.main([]), 2)
            with tempfile.TemporaryDirectory() as directory:
                self.assertEqual(
                    deployment_files.main(["not an image", "1.2.3", directory]), 1
                )


if __name__ == "__main__":
    unittest.main()
