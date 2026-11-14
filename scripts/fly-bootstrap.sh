#!/usr/bin/env bash
# One-time Fly.io setup for JobApplyAI (phase 1) — see
# docs/fly-deployment-notes.md for the full launch runbook.
#
# What it does, in order, each step check-before-create so re-running is
# safe:
#   1. Creates the Fly app (default name "jobapplyai") in the org.
#   2. Creates the persistent volume that holds the app's data directory
#      (phase 1: the SQLite database AND the uploaded resumes).
#   3. Sets the app's Fly secrets, taking values from your environment or
#      the repo's gitignored .env and prompting for anything missing.
#      Secret values are never printed and never written to a tracked
#      file; they are passed to Fly over stdin.
#
# It does NOT deploy. When it finishes it prints the remaining steps
# (FLY_API_TOKEN for GitHub Actions, first deploy, first admin).
#
# Overrides: FLY_APP_NAME, FLY_ORG, FLY_REGION, FLY_VOLUME_SIZE_GB.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="${FLY_APP_NAME:-jobapplyai}"
ORG="${FLY_ORG:-jobapplyai}"
REGION="${FLY_REGION:-sjc}"
VOLUME_NAME="jobapply_data"
VOLUME_SIZE_GB="${FLY_VOLUME_SIZE_GB:-5}"

if command -v flyctl >/dev/null 2>&1; then
  FLY="flyctl"
elif command -v fly >/dev/null 2>&1; then
  FLY="fly"
else
  echo "error: flyctl not found. Install it first: https://fly.io/docs/flyctl/install/" >&2
  exit 1
fi

if ! "$FLY" auth whoami >/dev/null 2>&1; then
  echo "error: not logged in to Fly.io. Run: $FLY auth login" >&2
  exit 1
fi

# --- Value lookup: environment, then the gitignored .env, then prompt ---

dotenv_value() {
  # $1 = variable name; prints its value from ./.env (nothing if absent)
  local name="$1" line="" value=""
  [[ -f .env ]] || return 0
  line="$(grep -E "^${name}=" .env | tail -n 1 || true)"
  [[ -n "$line" ]] || return 0
  value="${line#*=}"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "$value"
}

resolve_value() {
  # $1 = variable name; prints the environment value, else the .env value
  local name="$1" value=""
  value="$(printenv "$name" || true)"
  if [[ -z "$value" ]]; then
    value="$(dotenv_value "$name")"
  fi
  printf '%s' "$value"
}

prompt_value() {
  # $1 = variable name, $2 = "secret" to read without echo; prints the value
  local name="$1" mode="${2:-}" value=""
  if [[ ! -t 0 ]]; then
    echo "error: $name is not set and there is no terminal to prompt on." >&2
    echo "Set it in the environment or in ./.env and re-run." >&2
    exit 1
  fi
  printf '%s: ' "$name" >&2
  if [[ "$mode" == "secret" ]]; then
    read -r -s value
    printf '\n' >&2
  else
    read -r value
  fi
  printf '%s' "$value"
}

echo "Fly.io phase-1 setup: app '$APP_NAME', org '$ORG', region '$REGION'"

# --- 1. App ---------------------------------------------------------------

if "$FLY" apps list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$APP_NAME"; then
  echo "App '$APP_NAME' already exists — skipping create."
else
  echo "Creating app '$APP_NAME'..."
  if ! "$FLY" apps create "$APP_NAME" --org "$ORG"; then
    echo "error: could not create app '$APP_NAME'." >&2
    echo "Fly app names are globally unique; if this one is taken, re-run with" >&2
    echo "another name, e.g.:  FLY_APP_NAME=jobapplylive $0" >&2
    echo "and update 'app =' plus PUBLIC_BASE_URL / CORS_ORIGINS in fly.toml to match." >&2
    exit 1
  fi
fi

# --- 2. Volume --------------------------------------------------------------

if "$FLY" volumes list --app "$APP_NAME" --json 2>/dev/null | grep -qE "\"name\": *\"$VOLUME_NAME\""; then
  echo "Volume '$VOLUME_NAME' already exists — skipping create."
else
  echo "Creating ${VOLUME_SIZE_GB} GB volume '$VOLUME_NAME' in $REGION..."
  "$FLY" volumes create "$VOLUME_NAME" --app "$APP_NAME" --region "$REGION" --size "$VOLUME_SIZE_GB" --yes
fi

# --- 3. Secrets -------------------------------------------------------------
# Only names are ever listed or printed; values go to Fly over stdin in one
# batched import at the end. A secret whose name is already set on the app
# is skipped, so re-running never overwrites existing values.

existing_secrets=" $("$FLY" secrets list --app "$APP_NAME" 2>/dev/null | awk 'NR>1 {print $1}' | tr '\n' ' ' || true)"
pairs=""

add_secret() {
  # $1 = name, $2 = value; queues one KEY=VALUE line for the import
  pairs="${pairs}$1=$2
"
}

queue_secret() {
  # $1 = name, $2 = required|optional, $3 = secret|plain (prompt style)
  local name="$1" mode="$2" read_mode="${3:-secret}" value=""
  case "$existing_secrets" in
    *" $name "*)
      echo "$name is already set on the app — skipping."
      return 0
      ;;
  esac
  value="$(resolve_value "$name")"
  if [[ -z "$value" && "$mode" == "required" ]]; then
    value="$(prompt_value "$name" "$read_mode")"
  fi
  if [[ -n "$value" ]]; then
    add_secret "$name" "$value"
    echo "$name: will set."
  else
    echo "$name: not provided — skipping (optional)."
  fi
}

queue_secret SMTP_USER required plain
queue_secret SMTP_PASSWORD required secret
queue_secret ADMIN_EMAILS required plain

# The bootstrap invite is one-time: it exists only so the first admin can
# register while signup is invite-only, and it is unset right after (see
# the next steps below). Never re-add it silently on a re-run.
case "$existing_secrets" in
  *" JOBAPPLY_BOOTSTRAP_INVITE "*)
    echo "JOBAPPLY_BOOTSTRAP_INVITE is already set on the app — skipping."
    ;;
  *)
    invite="$(resolve_value JOBAPPLY_BOOTSTRAP_INVITE)"
    if [[ -z "$invite" && -t 0 ]]; then
      printf 'Set a one-time bootstrap invite? Only needed before the first admin registers [y/N]: ' >&2
      read -r answer
      case "$answer" in
        y | Y | yes | YES) invite="$(prompt_value JOBAPPLY_BOOTSTRAP_INVITE secret)" ;;
      esac
    fi
    if [[ -n "$invite" ]]; then
      add_secret JOBAPPLY_BOOTSTRAP_INVITE "$invite"
      echo "JOBAPPLY_BOOTSTRAP_INVITE: will set."
    else
      echo "JOBAPPLY_BOOTSTRAP_INVITE: not set (fine once the first admin has registered)."
    fi
    ;;
esac

queue_secret OPENAI_API_KEY optional secret
queue_secret ADZUNA_APP_ID optional plain
queue_secret ADZUNA_APP_KEY optional secret
queue_secret USAJOBS_API_KEY optional secret
queue_secret USAJOBS_USER_AGENT optional plain

if [[ -n "$pairs" ]]; then
  echo "Setting secrets on '$APP_NAME' (passed over stdin, never printed)..."
  printf '%s' "$pairs" | "$FLY" secrets import --app "$APP_NAME"
else
  echo "No new secrets to set."
fi

# --- Next steps -------------------------------------------------------------

cat <<EOF

Setup complete for '$APP_NAME'. Remaining steps:

1. Create the app-scoped deploy token and add it to GitHub as the
   FLY_API_TOKEN Actions secret (repo Settings -> Secrets and variables
   -> Actions). That token is the ONLY secret that lives in GitHub;
   every app secret stays in Fly Secrets.
       $FLY tokens create deploy --app $APP_NAME

2. Deploy: merge to main (GitHub Actions deploys automatically), or once
   by hand:
       $FLY deploy --app $APP_NAME --ha=false

3. Verify:
       curl https://$APP_NAME.fly.dev/api/health

4. Register the first admin with an ADMIN_EMAILS address and the
   bootstrap invite, verify from the emailed link, then remove the
   one-time secret:
       $FLY secrets unset JOBAPPLY_BOOTSTRAP_INVITE --app $APP_NAME
EOF
