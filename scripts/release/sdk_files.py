"""Builds a release's Python SDK files (sdk/python/README.md).

The SDK's wheel and source archive, built from the commit with the release's
version in place of the development placeholder of sdk/python/pyproject.toml,
so the package's metadata and `signalhub --version` name the release. The
repository's pyproject.toml is never rewritten: the build works on a copy. A
release attaches the files; CI builds them with a test version.

Before printing, the wheel is installed into a new virtual environment and
`signalhub --version` must report the version, so a release never attaches
files that would identify as something else.

Usage:
    sdk_files.py VERSION DIRECTORY
        Writes signalhub-VERSION.tar.gz and signalhub-VERSION-py3-none-any.whl
        to DIRECTORY and prints their paths. Needs the `build` package
        (.github/tools/requirements.txt) and network access for its isolated
        build environment.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SDK = ROOT / "sdk" / "python"

PLACEHOLDER = 'version = "0.0.0.dev0"\n'

# A release version (1.2.3) or a test version with a local label (0.0.0+ci),
# both valid PEP 440 versions that packaging keeps as written.
VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+(\+[a-z0-9]+)?")


class SdkFilesError(Exception):
    pass


def release_pyproject(source: str, version: str) -> str:
    """The SDK's pyproject.toml with `version` in place of the placeholder."""
    if not VERSION.fullmatch(version):
        raise SdkFilesError(f"not a version: {version!r}")
    if source.count(PLACEHOLDER) != 1:
        raise SdkFilesError(
            "sdk/python/pyproject.toml does not have the development placeholder"
        )
    return source.replace(PLACEHOLDER, f'version = "{version}"\n')


def file_names(version: str) -> tuple[str, str]:
    return f"signalhub-{version}.tar.gz", f"signalhub-{version}-py3-none-any.whl"


def build(version: str, directory: Path, sdk: Path = SDK) -> list[Path]:
    pyproject = release_pyproject((sdk / "pyproject.toml").read_text(), version)
    with tempfile.TemporaryDirectory() as work:
        source = Path(work) / "sdk"
        shutil.copytree(
            sdk, source, ignore=shutil.ignore_patterns("build", "*.egg-info")
        )
        (source / "pyproject.toml").write_text(pyproject)
        # Builds the source archive, then the wheel from it, so the archive is
        # proven complete.
        subprocess.run(
            [sys.executable, "-m", "build", "--outdir", str(directory), str(source)],
            check=True,
            stdout=sys.stderr,
        )
    paths = [directory / name for name in file_names(version)]
    for path in paths:
        if not path.is_file():
            raise SdkFilesError(f"the build did not write {path.name}")
    check(paths[1], version)
    return paths


def check(wheel: Path, version: str) -> None:
    """Installs the wheel apart from everything else and asks it its version."""
    with tempfile.TemporaryDirectory() as work:
        venv = Path(work) / "venv"
        subprocess.run([sys.executable, "-m", "venv", str(venv)], check=True)
        python = venv / "bin" / "python"
        subprocess.run(
            [str(python), "-m", "pip", "install", "--quiet", "--no-index", str(wheel)],
            check=True,
            stdout=sys.stderr,
        )
        reported = subprocess.run(
            [str(venv / "bin" / "signalhub"), "--version"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
    if reported != f"SignalHub {version}\n":
        raise SdkFilesError(f"the installed wheel reports {reported.strip()!r}")


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    version, directory = argv
    try:
        for path in build(version, Path(directory)):
            print(path)
    except (SdkFilesError, subprocess.CalledProcessError) as error:
        print(f"sdk_files.py: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
