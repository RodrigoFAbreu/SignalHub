"""Shared fixtures.

Database tests run against a real PostgreSQL server given by
SIGNALHUB_TEST_DATABASE_URL. Each test gets its own freshly created database,
dropped afterwards, so the suite never touches existing data on that server.
"""

import os
import uuid
from collections.abc import Iterator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

from signalhub.config import Settings
from signalhub.main import create_app

TEST_DATABASE_URL_VAR = "SIGNALHUB_TEST_DATABASE_URL"

# Nothing listens on port 1, so connections are refused immediately. This
# simulates a database outage deterministically and without network access.
UNREACHABLE_DATABASE_URL = (
    "postgresql+psycopg://signalhub:secret-password@127.0.0.1:1/signalhub"
)


@pytest.fixture(autouse=True)
def _isolate_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    # A developer's exported application settings must not leak into tests.
    for name in list(os.environ):
        if name.startswith("SIGNALHUB_") and name != TEST_DATABASE_URL_VAR:
            monkeypatch.delenv(name)


@pytest.fixture
def database_url() -> Iterator[str]:
    """URL of a new, empty database that is dropped after the test."""
    server_url = os.environ.get(TEST_DATABASE_URL_VAR)
    if not server_url:
        pytest.fail(
            f"{TEST_DATABASE_URL_VAR} is not set. Point it at a PostgreSQL server "
            "where the user may create databases (see docs/development.md)."
        )
    name = f"signalhub_test_{uuid.uuid4().hex}"
    admin = create_engine(server_url, isolation_level="AUTOCOMMIT")
    try:
        with admin.connect() as connection:
            connection.execute(text(f'CREATE DATABASE "{name}"'))
        yield (
            make_url(server_url)
            .set(database=name)
            .render_as_string(hide_password=False)
        )
        with admin.connect() as connection:
            connection.execute(text(f'DROP DATABASE "{name}" WITH (FORCE)'))
    finally:
        admin.dispose()


@pytest.fixture
def client(database_url: str) -> Iterator[TestClient]:
    with TestClient(create_app(Settings(database_url=database_url))) as test_client:
        yield test_client


@pytest.fixture
def unreachable_database_url() -> str:
    return UNREACHABLE_DATABASE_URL


@pytest.fixture
def unreachable_client(unreachable_database_url: str) -> Iterator[TestClient]:
    app = create_app(Settings(database_url=unreachable_database_url))
    with TestClient(app) as test_client:
        yield test_client
