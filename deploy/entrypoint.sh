#!/usr/bin/env bash
# Start uvicorn (API, loopback only) and Caddy (public, :8080) together.
# If either process exits, the container exits so Fly restarts the Machine.
set -euo pipefail

uvicorn app.main:app --host 127.0.0.1 --port 8000 &
UVICORN_PID=$!

caddy run --config /etc/caddy/Caddyfile &
CADDY_PID=$!

trap 'kill "${UVICORN_PID}" "${CADDY_PID}" 2>/dev/null || true' EXIT TERM INT
wait -n "${UVICORN_PID}" "${CADDY_PID}"
