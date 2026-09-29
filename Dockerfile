# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready, multi-stage)
#
# Build: docker build -t day12-agent:prod .
# Run:   docker run -e AGENT_API_KEY=... -e REDIS_URL=... -p 8000:8000 day12-agent:prod
# ═══════════════════════════════════════════════════════════════════

# ---------- Stage 1: builder — cài dependency, được phép nặng ----------
FROM python:3.11-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Chỉ copy requirements trước để layer pip install được cache
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ---------- Stage 2: runtime — chỉ mang theo kết quả ----------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

COPY --from=builder /install /usr/local

RUN useradd --create-home --uid 10001 appuser

WORKDIR /app

# Code copy SAU dependency — sửa code không làm mất cache pip install
COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser utils ./utils

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT', '8000') + '/health', timeout=4).read()" || exit 1

# exec để uvicorn là PID 1 và nhận SIGTERM trực tiếp
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
