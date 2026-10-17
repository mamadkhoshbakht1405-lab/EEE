#!/bin/sh
# Railway entrypoint for 3x-ui.
#  - listens on Railway's $PORT
#  - keeps DB on the Railway Volume (/etc/x-ui)
#  - first boot: sets username / password / secret base path (from env or random)
set -u

DB_DIR="${XUI_DB_FOLDER:-/etc/x-ui}"
LOG_DIR="${XUI_LOG_FOLDER:-/var/log/x-ui}"
MARK="$DB_DIR/.railway-initialized"

# If a path exists as a plain FILE (old broken deploy), move it away.
for d in "$DB_DIR" "$LOG_DIR"; do
  if [ -e "$d" ] && [ ! -d "$d" ]; then
    echo "[railway] $d is a file, renaming to $d.bak"
    mv "$d" "$d.bak"
  fi
done
mkdir -p "$DB_DIR" "$LOG_DIR"

export XUI_PORT="${PORT:-2053}"
export XUI_ENABLE_FAIL2BAN=false

rand() { tr -dc 'a-z0-9' </dev/urandom | head -c "$1"; }

if [ ! -f "$MARK" ]; then
  USER_NAME="${PANEL_USERNAME:-$(rand 8)}"
  USER_PASS="${PANEL_PASSWORD:-$(rand 16)}"
  BASE_PATH="${PANEL_BASE_PATH:-$(rand 12)}"
  BASE_PATH="/${BASE_PATH#/}"
  BASE_PATH="${BASE_PATH%/}/"

  /app/x-ui setting -port "$XUI_PORT" -username "$USER_NAME" -password "$USER_PASS" -webBasePath "$BASE_PATH"
  touch "$MARK"

  HOST="${RAILWAY_PUBLIC_DOMAIN:-<your-domain>.up.railway.app}"
  echo "=================================================="
  echo " 3x-ui first-run credentials (save them now!)"
  echo "  URL:      https://$HOST$BASE_PATH"
  echo "  Username: $USER_NAME"
  echo "  Password: $USER_PASS"
  echo "=================================================="
else
  # Keep port in sync; re-apply credentials only if explicitly set in env.
  /app/x-ui setting -port "$XUI_PORT" >/dev/null 2>&1
  if [ -n "${PANEL_USERNAME:-}" ] && [ -n "${PANEL_PASSWORD:-}" ]; then
    /app/x-ui setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" >/dev/null 2>&1
  fi
  if [ -n "${PANEL_BASE_PATH:-}" ]; then
    BP="/${PANEL_BASE_PATH#/}"; BP="${BP%/}/"
    /app/x-ui setting -webBasePath "$BP" >/dev/null 2>&1
  fi
fi

exec /app/x-ui
