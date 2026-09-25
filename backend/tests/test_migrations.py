import os
import subprocess
import sys
from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory

BACKEND_DIR = Path(__file__).resolve().parents[1]


def alembic(database_url: str, *args: str) -> subprocess.CompletedProcess[str]:
    # Runs the real CLI, exactly as operators and the Compose migrate service do.
    return subprocess.run(
        [sys.executable, "-m", "alembic", *args],
        cwd=BACKEND_DIR,
        env={**os.environ, "SIGNALHUB_DATABASE_URL": database_url},
        capture_output=True,
        text=True,
        check=False,
    )


def test_migration_history_has_a_single_head() -> None:
    scripts = ScriptDirectory.from_config(Config(BACKEND_DIR / "alembic.ini"))

    assert len(scripts.get_heads()) <= 1


def test_upgrade_matches_models_and_downgrade_reverts(database_url: str) -> None:
    upgrade = alembic(database_url, "upgrade", "head")
    assert upgrade.returncode == 0, upgrade.stderr

    # Fails when models change without a matching migration.
    check = alembic(database_url, "check")
    assert check.returncode == 0, check.stdout + check.stderr

    downgrade = alembic(database_url, "downgrade", "base")
    assert downgrade.returncode == 0, downgrade.stderr
