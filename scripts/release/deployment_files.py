"""Packs a release's deployment files (docs/deployment.md).

The files an operator needs to run SignalHub from its published images:
compose.yaml, .env.example and proxy/Caddyfile, as in the repository, except
that compose.yaml runs the given backend image instead of building one from
source. A release attaches the archive; CI packs one with the image it built
for the commit under test.

Usage:
    deployment_files.py IMAGE VERSION DIRECTORY
        Writes DIRECTORY/signalhub-VERSION-deployment.tar.gz and prints its path.
        IMAGE is the backend image reference, such as
        ghcr.io/rodrigofabreu/signalhub:1.2.3@sha256:...

Only the standard library is used so the script runs on any runner without setup.
"""

from __future__ import annotations

import gzip
import io
import re
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = ("compose.yaml", ".env.example", "proxy/Caddyfile")

# The backend's build in the repository's compose.yaml, which a release's file
# replaces with its image.
SOURCE_BUILD = """\
    # Built from source. A release's deployment files replace these two lines
    # with the release's published image (scripts/release/deployment_files.py).
    build: ./backend
    image: signalhub-backend:local
"""

# A plain image reference: no whitespace or characters YAML or Compose would read.
IMAGE = re.compile(r"[a-z0-9][a-z0-9._/:@-]*")
VERSION = re.compile(r"[0-9A-Za-z][0-9A-Za-z.+-]*")


class DeploymentFilesError(Exception):
    pass


def release_compose(source: str, image: str, version: str) -> str:
    """The repository's compose.yaml, running `image` instead of a local build."""
    if not IMAGE.fullmatch(image):
        raise DeploymentFilesError(f"not an image reference: {image!r}")
    if source.count(SOURCE_BUILD) != 1:
        raise DeploymentFilesError(
            "compose.yaml does not build the backend as expected"
        )
    return source.replace(
        SOURCE_BUILD,
        f"    # SignalHub {version}'s published backend image.\n    image: {image}\n",
    )


def archive_name(version: str) -> str:
    return f"signalhub-{version}-deployment.tar.gz"


def pack(image: str, version: str, directory: Path, root: Path = ROOT) -> Path:
    if not VERSION.fullmatch(version):
        raise DeploymentFilesError(f"not a version: {version!r}")
    contents = {name: (root / name).read_bytes() for name in FILES}
    compose = release_compose(contents["compose.yaml"].decode(), image, version)
    contents["compose.yaml"] = compose.encode()
    path = directory / archive_name(version)
    # Fixed times, owners and modes: the archive depends only on its contents.
    with (
        path.open("wb") as file,
        gzip.GzipFile(filename="", mode="wb", fileobj=file, mtime=0) as compressed,
        tarfile.open(
            fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT
        ) as archive,
    ):
        for name, data in contents.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            archive.addfile(info, io.BytesIO(data))
    return path


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    image, version, directory = argv
    try:
        print(pack(image, version, Path(directory)))
    except DeploymentFilesError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
