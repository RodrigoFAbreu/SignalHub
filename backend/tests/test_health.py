import logging

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, exc, text

from signalhub.db import get_session


def test_liveness_reports_ok(client: TestClient) -> None:
    response = client.get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_liveness_does_not_depend_on_the_database(
    unreachable_client: TestClient,
) -> None:
    response = unreachable_client.get("/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_readiness_reports_ok_when_database_is_reachable(client: TestClient) -> None:
    response = client.get("/health/ready")

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "checks": {"database": "ok"}}


def test_readiness_reports_unavailable_when_database_is_unreachable(
    unreachable_client: TestClient, caplog: pytest.LogCaptureFixture
) -> None:
    with caplog.at_level(logging.WARNING, logger="signalhub.health"):
        response = unreachable_client.get("/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "status": "unavailable",
        "checks": {"database": "unavailable"},
    }
    assert "database unavailable" in caplog.text
    assert "secret-password" not in response.text
    assert "secret-password" not in caplog.text


def test_readiness_reports_unavailable_on_errors_without_a_driver_cause(
    unreachable_client: TestClient,
) -> None:
    class ExhaustedPoolSession:
        def execute(self, statement: object) -> None:
            raise exc.TimeoutError("QueuePool limit reached")

    app = unreachable_client.app
    app.dependency_overrides[get_session] = ExhaustedPoolSession

    response = unreachable_client.get("/health/ready")

    assert response.status_code == 503


def test_readiness_recovers_after_server_closes_connections(
    client: TestClient, database_url: str
) -> None:
    assert client.get("/health/ready").status_code == 200

    # Simulates a database restart: every pooled connection is closed server-side.
    admin = create_engine(database_url)
    with admin.connect() as connection:
        connection.execute(
            text(
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
                "WHERE datname = current_database() AND pid <> pg_backend_pid()"
            )
        )
    admin.dispose()

    assert client.get("/health/ready").status_code == 200
