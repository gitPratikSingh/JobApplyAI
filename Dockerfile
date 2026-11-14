# JobApplyAI — production image (Fly.io).
#
# The codebase, as it stands on main, is two pieces:
#   * a FastAPI backend (backend/app/main.py, served by uvicorn) that is
#     API-only — it does NOT serve the frontend, and
#   * a React/Vite frontend that calls the API via relative /api/... paths
#     (no API base URL is baked in), so in production it must be served
#     from the same origin as the API.
# This image therefore runs a tiny Caddy front door: it serves the built
# frontend statically and reverse-proxies /api/* (HTTP + the pre-fill
# session WebSocket) to uvicorn on loopback. See deploy/Caddyfile.

# ---- Stage 1: build the frontend -------------------------------------------
FROM node:20-slim AS frontend-build
WORKDIR /build/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# ---- Stage 2: grab the Caddy binary ----------------------------------------
FROM caddy:2-alpine AS caddy-bin

# ---- Stage 3: runtime -------------------------------------------------------
# Playwright's official Python image, in the exact version pinned in
# backend/requirements.txt (playwright==1.64.0). It ships Chromium and all
# of its system libraries, which the streamed pre-fill sessions require
# (backend/app/prefill_sessions.py launches headless Chromium via
# Playwright; the README's hosted setup requires `playwright install
# chromium` on the server — this image is that, pre-baked).
FROM mcr.microsoft.com/playwright/python:v1.64.0-noble

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/backend \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

COPY backend/requirements.txt ./backend/requirements.txt
RUN pip install --no-cache-dir -r backend/requirements.txt

COPY backend/ ./backend/
COPY --from=frontend-build /build/frontend/dist ./frontend/dist
COPY --from=caddy-bin /usr/bin/caddy /usr/bin/caddy
COPY deploy/Caddyfile /etc/caddy/Caddyfile
COPY deploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /data

EXPOSE 8080
CMD ["/entrypoint.sh"]
