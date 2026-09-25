"""Application factory. Run with `uvicorn --factory signalhub.main:create_app`."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI

from signalhub import health
from signalhub.config import Settings
from signalhub.db import create_db_engine, create_session_factory


def create_app(settings: Settings | None = None) -> FastAPI:
    """Build the application. Settings are read from the environment unless
    given. No database connection is opened until a request needs one, so the
    process starts, and reports liveness, even while the database is down."""
    settings = settings or Settings()
    engine = create_db_engine(settings.database_url.get_secret_value())

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        yield
        engine.dispose()

    app = FastAPI(title="SignalHub", lifespan=lifespan)
    app.state.session_factory = create_session_factory(engine)
    app.include_router(health.router)
    return app
