# SignalHub backend image. Build context: this directory.

FROM python:3.12-slim AS build

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv

RUN pip install --no-cache-dir uv==0.12.19

WORKDIR /src
# Dependencies first, so source changes do not invalidate this layer.
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-install-project
COPY src ./src
RUN uv sync --locked --no-dev --no-editable


FROM python:3.12-slim

RUN useradd --system --uid 10001 --no-create-home signalhub

# Same path as in the build stage: virtualenv scripts use absolute paths.
COPY --from=build /opt/venv /opt/venv
WORKDIR /app
COPY alembic.ini ./
COPY migrations ./migrations

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER signalhub
EXPOSE 8000

# Liveness only: the image cannot assume where its database is. Readiness is
# available at /health/ready for orchestrators that route traffic.
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health/live', timeout=2)"]

CMD ["uvicorn", "signalhub.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
