# ── builder stage ──────────────────────────────────────────────────────────────
FROM python:3.14-rc-slim AS builder

# Install UV
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Use the system Python (3.14-rc) rather than downloading a managed version.
# .python-version is excluded via .dockerignore to avoid version pin conflicts.
ENV UV_PYTHON_PREFERENCE=only-system

WORKDIR /app

# Copy dependency manifests and install deps (no project code yet)
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project --no-python-downloads

# Copy application source
COPY . .

# Install the project itself
RUN uv sync --frozen --no-python-downloads

# ── runtime stage ──────────────────────────────────────────────────────────────
FROM python:3.14-rc-slim

# Install ffmpeg (required at runtime for audio stream capture)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ffmpeg && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV UV_PYTHON_PREFERENCE=only-system

# Copy installed venv + app from builder
COPY --from=builder /app /app

CMD ["/app/.venv/bin/python", "main.py"]
