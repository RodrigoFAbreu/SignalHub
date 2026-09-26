"""Tests of sdk_files.py against the SDK's own pyproject.toml.

The build itself needs network access for its isolated environment, so CI's
Python job runs it (as the release does); these tests need neither.
"""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import sdk_files
from sdk_files import SdkFilesError, file_names, release_pyproject

ROOT = Path(__file__).resolve().parents[2]


class ReleasePyprojectTest(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "sdk" / "python" / "pyproject.toml").read_text()

    def test_the_repository_holds_the_development_placeholder(self):
        self.assertIn('\nversion = "0.0.0.dev0"\n', self.source)

    def test_sets_the_release_version(self):
        pyproject = release_pyproject(self.source, "1.2.3")
        self.assertIn('\nversion = "1.2.3"\n', pyproject)

    def test_accepts_a_test_version_with_a_local_label(self):
        pyproject = release_pyproject(self.source, "0.0.0+ci")
        self.assertIn('\nversion = "0.0.0+ci"\n', pyproject)

    def test_changes_nothing_else(self):
        pyproject = release_pyproject(self.source, "1.2.3")
        removed = set(self.source.splitlines()) - set(pyproject.splitlines())
        added = set(pyproject.splitlines()) - set(self.source.splitlines())
        self.assertEqual(removed, {'version = "0.0.0.dev0"'})
        self.assertEqual(added, {'version = "1.2.3"'})

    def test_refuses_what_is_not_a_version(self):
        for version in ("", "v1.2.3", "1.2", "1.2.3-ci", "1.2.3\nname = 'x'"):
            with self.subTest(version=version), self.assertRaises(SdkFilesError):
                release_pyproject(self.source, version)

    def test_refuses_a_pyproject_without_the_placeholder(self):
        for source in (
            self.source.replace('"0.0.0.dev0"', '"0.1.0"'),
            self.source + 'version = "0.0.0.dev0"\n',
        ):
            with self.subTest(source=source), self.assertRaises(SdkFilesError):
                release_pyproject(source, "1.2.3")


class BuildTest(unittest.TestCase):
    def test_names_the_files_as_the_build_does(self):
        self.assertEqual(
            file_names("1.2.3"),
            ("signalhub-1.2.3.tar.gz", "signalhub-1.2.3-py3-none-any.whl"),
        )

    def test_refuses_before_building_anything(self):
        stderr = io.StringIO()
        with (
            tempfile.TemporaryDirectory() as directory,
            mock.patch("subprocess.run") as run,
            contextlib.redirect_stderr(stderr),
        ):
            status = sdk_files.main(["v1.2.3", directory])

        self.assertEqual(status, 1)
        run.assert_not_called()
        self.assertIn("not a version: 'v1.2.3'", stderr.getvalue())

    def test_usage(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(sdk_files.main([]), 2)
        self.assertIn("Usage:", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
