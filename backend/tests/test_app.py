import pytest
from fastapi.testclient import TestClient

from signalhub.main import create_app


def test_starts_without_a_database_connection(unreachable_client: TestClient) -> None:
    # Startup opens no connection, so an outage cannot stop the process from
    # booting; readiness reports the outage instead.
    assert unreachable_client.get("/health/live").status_code == 200


def test_reads_settings_from_environment(
    monkeypatch: pytest.MonkeyPatch, unreachable_database_url: str
) -> None:
    monkeypatch.setenv("SIGNALHUB_DATABASE_URL", unreachable_database_url)

    with TestClient(create_app()) as client:
        assert client.get("/health/live").status_code == 200


def test_fails_fast_without_configuration() -> None:
    with pytest.raises(ValueError, match="database_url"):
        create_app()


def test_publishes_health_endpoints_in_openapi_schema(
    unreachable_client: TestClient,
) -> None:
    paths = unreachable_client.get("/openapi.json").json()["paths"]

    assert set(paths) == {"/health/live", "/health/ready"}
