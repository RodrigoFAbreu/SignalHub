"""Transaction semantics of the request-scoped DbSession dependency."""

from collections.abc import Iterator

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from signalhub.config import Settings
from signalhub.db import DbSession
from signalhub.main import create_app

INSERT = text("INSERT INTO probe (value) VALUES (:value)")


@pytest.fixture
def app(database_url: str) -> Iterator[FastAPI]:
    engine = create_engine(database_url)
    with engine.begin() as connection:
        # The deferred unique constraint is only checked at COMMIT, which lets
        # a test make the commit itself fail.
        connection.execute(
            text(
                "CREATE TABLE probe (value text, "
                "CONSTRAINT probe_value_key UNIQUE (value) DEFERRABLE INITIALLY DEFERRED)"
            )
        )
    engine.dispose()

    app = create_app(Settings(database_url=database_url))

    @app.post("/probe/{value}")
    def insert(value: str, session: DbSession) -> dict[str, str]:
        session.execute(INSERT, {"value": value})
        return {"inserted": value}

    @app.post("/probe/{value}/then-fail")
    def insert_then_fail(value: str, session: DbSession) -> None:
        session.execute(INSERT, {"value": value})
        raise RuntimeError("handler failed after writing")

    @app.post("/probe/{value}/twice")
    def insert_twice(value: str, session: DbSession) -> dict[str, str]:
        for _ in range(2):
            session.execute(INSERT, {"value": value})
        return {"inserted": value}

    yield app


@pytest.fixture
def client(app: FastAPI) -> Iterator[TestClient]:
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


def stored_values(database_url: str) -> list[str]:
    engine = create_engine(database_url)
    try:
        with engine.connect() as connection:
            return list(
                connection.scalars(text("SELECT value FROM probe ORDER BY value"))
            )
    finally:
        engine.dispose()


def test_commits_when_handler_succeeds(client: TestClient, database_url: str) -> None:
    assert client.post("/probe/a").status_code == 200

    assert stored_values(database_url) == ["a"]


def test_rolls_back_when_handler_raises(client: TestClient, database_url: str) -> None:
    assert client.post("/probe/a/then-fail").status_code == 500

    assert stored_values(database_url) == []


def test_commit_failure_is_reported_to_the_client(
    client: TestClient, database_url: str
) -> None:
    # The commit runs before the response is sent, so a failed commit can
    # never be acknowledged as a success.
    assert client.post("/probe/a/twice").status_code == 500

    assert stored_values(database_url) == []
