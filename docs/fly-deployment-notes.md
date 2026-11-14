# Fly.io deployment notes (launch runbook)

Status: **prepared, not yet deployed.** This document accompanies the
deployment artifacts added alongside it. Phase 1 is deliberately the
smallest shape that works: **one Fly app, SQLite on a persistent volume.**
The Postgres migration is phase 2 (see the end of this document).

| File | Purpose |
|---|---|
| `Dockerfile` | Builds the frontend, then a runtime image (Playwright/Chromium + backend + Caddy) |
| `.dockerignore` | Keeps committed `node_modules`, local `data/`, and `.env` out of the image |
| `deploy/Caddyfile` | Serves the built frontend and proxies `/api/*` to uvicorn on loopback |
| `deploy/entrypoint.sh` | Runs uvicorn + Caddy together; container exits if either dies |
| `fly.toml` | The one web app: `shared-cpu-2x` / 2 GB Machine in `sjc`, always-on, volume at `/data` |
| `scripts/fly-bootstrap.sh` | One-time setup (app, volume, Fly secrets) — check-before-create, safe to re-run; does not deploy |
| `.github/workflows/fly-deploy.yml` | Deploys the web app on push to `main` via `FLY_API_TOKEN` |

This branch changes **no application code**: the backend and frontend are
untouched, and `backend/requirements.txt` is unchanged.

Decisions behind this shape live in
`docs/hosting-domain-flyio-github-deployment-adr.md` (Fly over
Render/AWS, lean launch cost, GitHub Actions deploys, custom domain
later). The phase split — SQLite first, Postgres as a later migration —
was settled when the launch prep was reviewed.

## How the pieces fit

- The FastAPI backend is **API-only** — it serves no static files — and the
  React frontend calls relative `/api/...` URLs. So the container runs a
  small **Caddy** process in front: static frontend at the origin root,
  `/api/*` (including the pre-fill WebSocket
  `/api/prefill-sessions/{id}/stream`) proxied to uvicorn on
  `127.0.0.1:8000`. Fly terminates TLS and forwards to Caddy on port 8080.
- The runtime base image is Playwright's official Python image in the same
  version the backend pins (`playwright==1.64.0`), because streamed
  pre-fill sessions launch headless Chromium on the server.
- The app reads all configuration from environment variables
  (`backend/app/config.py`, `backend/app/db.py`). Tables are created and
  upgraded automatically at startup (`create_all` + `upgrade_schema()`),
  so there is no migration step in the deploy.
- `fly.toml` points `JOBAPPLY_DATA_DIR` at `/data`, a Fly **volume**.
  Everything stateful lives under that directory: in phase 1 that is the
  **SQLite database** (`/data/jobapply.db` — `db.py` uses it whenever
  `DATABASE_URL` is unset, and `fly.toml` deliberately does not set one)
  and the **uploaded resumes** (`/data/uploads`). Without the volume,
  both would vanish on every deploy. (Pre-fill browser profiles also live
  under the data dir but are ephemeral by design — they are wiped when a
  session closes.)
- One always-on Machine: auto-stop is off because streamed pre-fill
  sessions hold live browser state in this process's memory.

## Secrets and configuration at deploy time

Non-secret config is in `fly.toml`'s `[env]` (`JOBAPPLY_HOSTED`,
`SESSION_COOKIE_SECURE`, `PUBLIC_BASE_URL`, `CORS_ORIGINS`, `SMTP_HOST`,
`SMTP_PORT`, `SMTP_FROM`, `MAX_RUNS_PER_DAY`, `FORMFILL_HEADLESS`,
`JOBAPPLY_DATA_DIR`). Everything sensitive lives **only in Fly Secrets**
— never in this repo, never in GitHub. `scripts/fly-bootstrap.sh` sets
them from the operator's environment or the repo's gitignored `.env`,
prompting for anything missing, and never prints a value.

### Web app (`--app jobapplyai`)

| Variable | Required | Where the value comes from |
|---|---|---|
| `SMTP_USER` | Yes | `jobapplyai.app@gmail.com` — the dedicated Gmail account created for this project |
| `SMTP_PASSWORD` | Yes | The Gmail App Password for that account (it lives only in a gitignored `.env` on the operator's machine — copy it from there at setup time, never via git) |
| `ADMIN_EMAILS` | Yes | Comma-separated admin email(s) chosen by the operators |
| `JOBAPPLY_BOOTSTRAP_INVITE` | First launch only | A one-time invite code the operator picks; used to register the first admin, then unset (`fly secrets unset`) |
| `OPENAI_API_KEY` | Optional | An OpenAI API key, if tailored resumes/cover letters should be on at launch (the app's core flows work without it) |
| `ADZUNA_APP_ID` / `ADZUNA_APP_KEY` | Optional | Free keys from developer.adzuna.com, if that job source is wanted at launch |
| `USAJOBS_API_KEY` / `USAJOBS_USER_AGENT` | Optional | Free key from developer.usajobs.gov; user agent is the registered email |

### GitHub

| Secret | Where the value comes from |
|---|---|
| `FLY_API_TOKEN` | Output of `fly tokens create deploy --app jobapplyai` (app-scoped deploy token). This is the only secret in GitHub, and it can only deploy this one app. Must be added by a repo admin — Bhanu for the upstream repo, or the workflow runs from Pratik's fork instead (open decision in the ADR) |

## One-time setup sequence

```bash
# 1. App + volume + Fly secrets (idempotent; safe to re-run)
scripts/fly-bootstrap.sh
#    Overrides if needed: FLY_APP_NAME, FLY_ORG, FLY_REGION,
#    FLY_VOLUME_SIZE_GB. If the default app name is taken, the script
#    stops and suggests FLY_APP_NAME=jobapplylive.

# 2. Deploy token -> GitHub Actions secret FLY_API_TOKEN (repo admin)
fly tokens create deploy --app jobapplyai

# 3. First deploy: merge this branch's PR, or by hand once:
fly deploy --app jobapplyai --ha=false

# 4. Verify, then bootstrap the first admin
curl https://jobapplyai.fly.dev/api/health        # {"ok": true}
#    Register with an ADMIN_EMAILS address + the bootstrap invite,
#    verify from the emailed link, then:
fly secrets unset JOBAPPLY_BOOTSTRAP_INVITE --app jobapplyai
```

After step 3, every merge to `main` deploys automatically via the
GitHub Actions workflow; rollback is a revert on GitHub.

## Data and backups (phase 1: SQLite on a volume)

- The 5 GB volume (`jobapply_data`, ≈ $0.75/mo) holds the SQLite file
  and the uploads. Fly takes automatic daily volume snapshots (5
  retained by default); restoring means creating a new volume from a
  snapshot and pointing the app at it.
- Backups are our job (accepted trade-off in the ADR). Before risky
  changes, also pull a copy of the database file out:
  `fly ssh sftp get /data/jobapply.db ./jobapply-backup.db --app jobapplyai`
- The volume pins the app to one Machine in one zone, which matches the
  one-Machine launch shape. Scaling out later means moving state off
  local disk first — that is exactly what phase 2 does.

## Phase 2 (later, deliberately not in this PR)

Move the database to Postgres: a separate small Fly app (or managed
Postgres, re-priced then), a `DATABASE_URL` Fly secret on the web app,
and the `psycopg` driver added to `backend/requirements.txt` — on main
today there is no Postgres driver, so that addition is part of the
phase-2 change, not this one. Data migration is a dump/load of a small
SQLite file at beta scale.

## Later: the custom domain

The first deploy targets `https://jobapplyai.fly.dev`. Attaching
`jobapplylive.com` is a separate, later step (ADR step 7): add the domain
in Fly (`fly certs add jobapplylive.com --app jobapplyai`), set the DNS
records Fly specifies at Porkbun, wait for the certificate, then change
`PUBLIC_BASE_URL` and `CORS_ORIGINS` in `fly.toml` to
`https://jobapplylive.com` and redeploy — email links and CORS follow
those two variables.

## Watch items

- **Chromium sandbox:** both browser launches (`prefill_sessions.py`,
  `agent/formfill.py`) use Playwright defaults with no `--no-sandbox`
  argument. The Playwright image is the standard way to run this and Fly
  Machines are full VMs (user namespaces available), so it is expected to
  work; if session startup fails with sandbox errors in the logs, the fix
  is a small `args=["--no-sandbox"]` addition at those two call sites.
- **Single Machine:** one web Machine is a single point of failure
  (accepted for the beta in the ADR), and the `/data` volume pins it to
  one zone.
- **Committed clutter:** `frontend/node_modules`, `data/jobapply.db`, and
  `__pycache__` files are committed on main. `.dockerignore` keeps them
  out of the image, but a repo cleanup would shrink clones and builds.

## Open decisions for Pratik

1. **Fly app name** — `jobapplyai` is assumed in `fly.toml`; availability
   is unverified (names are global). Fallback: `jobapplylive`. The
   bootstrap script stops with that suggestion if the name is taken.
2. **Who adds `FLY_API_TOKEN`** — Bhanu (upstream repo admin) or run the
   workflow from the fork (carried over from the ADR).
3. **Optional keys at launch** — OpenAI / Adzuna / USAJobs: set them for
   day one, or launch without and add later (all are read at startup;
   adding one later is a `fly secrets set` + restart).
4. **Caddy vs. code change** — this prep keeps the backend untouched and
   fronts it with Caddy. If Bhanu prefers one process, the alternative is
   a small patch to `main.py` mounting `frontend/dist` via `StaticFiles`
   with an SPA fallback; the Dockerfile then drops Caddy.
