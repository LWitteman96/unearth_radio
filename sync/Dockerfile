# ── builder stage ──────────────────────────────────────────────────────────────
FROM python:3.14-rc-slim AS builder

# Install UV
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Tell UV to use the system Python (3.14 from the base image) rather than
# downloading its own — avoids the .python-version pin conflicting.
ENV UV_PYTHON_PREFERENCE=only-system

WORKDIR /app

# Copy dependency manifests
COPY pyproject.toml uv.lock ./

# Install dependencies (no project code yet, ignore python-version pin)
RUN uv sync --frozen --no-install-project --no-python-downloads

# Copy application source
COPY . .

# Install the project itself
RUN uv sync --frozen --no-python-downloads

# ── runtime stage ──────────────────────────────────────────────────────────────
FROM python:3.14-rc-slim

WORKDIR /app

ENV UV_PYTHON_PREFERENCE=only-system

# Copy installed venv + app from builder
COPY --from=builder /app /app

CMD ["/app/.venv/bin/python", "main.py"]
