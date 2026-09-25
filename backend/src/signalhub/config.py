"""Runtime configuration, read from environment variables."""

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url
from sqlalchemy.exc import ArgumentError

REQUIRED_DRIVER = "postgresql+psycopg"


class Settings(BaseSettings):
    """Backend settings. Each field is read from `SIGNALHUB_<FIELD_NAME>`."""

    # Validation errors must not echo inputs: the database URL holds a password.
    model_config = SettingsConfigDict(
        env_prefix="SIGNALHUB_", frozen=True, hide_input_in_errors=True
    )

    # Required, with no default: the URL carries the database password, and a
    # built-in fallback could silently point a deployment at the wrong database.
    database_url: SecretStr

    @field_validator("database_url")
    @classmethod
    def _require_psycopg_postgres_url(cls, value: SecretStr) -> SecretStr:
        try:
            url = make_url(value.get_secret_value())
        except ArgumentError:
            raise ValueError("must be a valid SQLAlchemy database URL") from None
        if url.drivername != REQUIRED_DRIVER:
            raise ValueError(f"must use the {REQUIRED_DRIVER}:// scheme")
        return value
