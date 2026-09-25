"""Liveness and readiness probes for orchestrators and monitoring."""

import logging

from fastapi import APIRouter, status
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from signalhub.db import DbSession

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/health", tags=["health"])


@router.get("/live")
def live() -> dict[str, str]:
    """The process is up and serving requests. Checks no dependencies."""
    return {"status": "ok"}


@router.get("/ready", responses={503: {"description": "A dependency is unavailable."}})
def ready(session: DbSession) -> JSONResponse:
    """The service can do useful work: the database accepts queries."""
    try:
        session.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        # Details stay in the server log; the response must not reveal
        # connection information to unauthenticated callers. One line, not a
        # traceback, because probes repeat every few seconds during an outage.
        # Driver errors (`orig`) read better than SQLAlchemy's wrapper text, but
        # not every SQLAlchemyError wraps one (pool timeouts do not).
        cause = getattr(exc, "orig", None) or exc
        logger.warning("Readiness check failed: database unavailable: %s", cause)
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={"status": "unavailable", "checks": {"database": "unavailable"}},
        )
    return JSONResponse(content={"status": "ok", "checks": {"database": "ok"}})
