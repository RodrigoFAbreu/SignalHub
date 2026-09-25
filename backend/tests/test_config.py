import pytest
from pydantic import ValidationError

from signalhub.config import Settings

VALID_URL = "postgresql+psycopg://signalhub:secret-password@db.example:5432/signalhub"


def test_reads_database_url_from_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("SIGNALHUB_DATABASE_URL", VALID_URL)

    assert Settings().database_url.get_secret_value() == VALID_URL


def test_database_url_is_required() -> None:
    with pytest.raises(ValidationError, match="database_url"):
        Settings()


@pytest.mark.parametrize(
    "url",
    [
        "postgresql://signalhub:secret-password@db.example/signalhub",
        "postgresql+psycopg2://signalhub:secret-password@db.example/signalhub",
        "sqlite:///secret-password.db",
    ],
)
def test_rejects_urls_without_the_psycopg_postgres_driver(url: str) -> None:
    with pytest.raises(ValidationError, match=r"postgresql\+psycopg://") as error:
        Settings(database_url=url)

    assert "secret-password" not in str(error.value)


def test_rejects_malformed_url() -> None:
    with pytest.raises(ValidationError, match="valid SQLAlchemy database URL") as error:
        Settings(database_url="not a url secret-password")

    assert "secret-password" not in str(error.value)


def test_database_password_is_hidden_from_repr() -> None:
    settings = Settings(database_url=VALID_URL)

    assert "secret-password" not in repr(settings)
    assert "secret-password" not in str(settings)
