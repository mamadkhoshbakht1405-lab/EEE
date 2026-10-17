#!/bin/sh
# Railway entrypoint for 3x-ui (single public port, many services).
#
#   Railway domain  ->  nginx on $PORT
#                         |- /<WS path>   -> xray inbound on 127.0.0.1:<port>  (WS_ROUTES)
#                         `- everything else -> 3x-ui panel on 127.0.0.1:$PANEL_INTERNAL_PORT
#
# So ONE "Generate Domain" serves the panel AND all inbounds.
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

PUBLIC_PORT="${PORT:-2053}"
PANEL_PORT="${PANEL_INTERNAL_PORT:-12053}"
[ "$PANEL_PORT" = "$PUBLIC_PORT" ] && PANEL_PORT=$((PANEL_PORT + 1))
WS_ROUTES_VALUE="${WS_ROUTES:-/ws443=10443,/ws8443=18443}"

export XUI_PORT="$PANEL_PORT"
export XUI_ENABLE_FAIL2BAN=false

rand() { tr -dc 'a-z0-9' </dev/urandom | head -c "$1"; }

# ---------------------------------------------------------------- panel setup
if [ ! -f "$MARK" ]; then
  USER_NAME="${PANEL_USERNAME:-$(rand 8)}"
  USER_PASS="${PANEL_PASSWORD:-$(rand 16)}"
  BASE_PATH="${PANEL_BASE_PATH:-$(rand 12)}"
  BASE_PATH="/${BASE_PATH#/}"
  BASE_PATH="${BASE_PATH%/}/"

  /app/x-ui setting -port "$PANEL_PORT" -username "$USER_NAME" -password "$USER_PASS" -webBasePath "$BASE_PATH"
  touch "$MARK"

  HOST="${RAILWAY_PUBLIC_DOMAIN:-<your-domain>.up.railway.app}"
  echo "=================================================="
  echo " 3x-ui first-run credentials (save them now!)"
  echo "  URL:      https://$HOST$BASE_PATH"
  echo "  Username: $USER_NAME"
  echo "  Password: $USER_PASS"
  echo "=================================================="
else
  /app/x-ui setting -port "$PANEL_PORT" >/dev/null 2>&1
  if [ -n "${PANEL_USERNAME:-}" ] && [ -n "${PANEL_PASSWORD:-}" ]; then
    /app/x-ui setting -username "$PANEL_USERNAME" -password "$PANEL_PASSWORD" >/dev/null 2>&1
  fi
  if [ -n "${PANEL_BASE_PATH:-}" ]; then
    BP="/${PANEL_BASE_PATH#/}"; BP="${BP%/}/"
    /app/x-ui setting -webBasePath "$BP" >/dev/null 2>&1
  fi
fi

# ------------------------------------------------------------ nginx (router)
NGX_CONF=/tmp/nginx.conf
ROUTES_CONF=/tmp/ws-routes.conf
mkdir -p /tmp/nginx_client /tmp/nginx_proxy
: > "$ROUTES_CONF"

echo "[railway] public port: $PUBLIC_PORT | panel (internal): $PANEL_PORT"
echo "$WS_ROUTES_VALUE" | tr ',' '\n' | while IFS= read -r route; do
  route=$(printf '%s' "$route" | tr -d ' \r')
  [ -z "$route" ] && continue
  wpath="${route%%=*}"
  wport="${route#*=}"
  case "$wpath" in /*) ;; *) echo "[railway] WARNING: skipping route '$route' (path must start with /)"; continue ;; esac
  case "$wport" in ''|*[!0-9]*) echo "[railway] WARNING: skipping route '$route' (port must be a number)"; continue ;; esac
  cat >> "$ROUTES_CONF" <<ROUTE
    location ^~ $wpath {
        proxy_pass http://127.0.0.1:$wport;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
        proxy_request_buffering off;
    }
ROUTE
  echo "[railway] route: $wpath -> 127.0.0.1:$wport"
done

write_nginx_conf() {
  # $1 = listen directives
  cat > "$NGX_CONF" <<CONF
worker_processes 1;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;
events { worker_connections 4096; }
http {
    access_log off;
    client_body_temp_path /tmp/nginx_client;
    proxy_temp_path /tmp/nginx_proxy;
    client_max_body_size 100m;

    map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }
    map \$http_x_forwarded_proto \$fproto { default \$http_x_forwarded_proto; '' \$scheme; }

    server {
        $1
        server_name _;

        include $ROUTES_CONF;

        location / {
            proxy_pass http://127.0.0.1:$PANEL_PORT;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
            proxy_set_header Host \$http_host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$fproto;
            proxy_read_timeout 3600s;
        }
    }
}
CONF
}

write_nginx_conf "listen [::]:$PUBLIC_PORT ipv6only=off;"
if ! nginx -t -c "$NGX_CONF" >/dev/null 2>&1; then
  echo "[railway] IPv6 listen failed, falling back to IPv4 only"
  write_nginx_conf "listen $PUBLIC_PORT;"
fi
if ! nginx -t -c "$NGX_CONF"; then
  echo "[railway] FATAL: nginx config invalid"
  exit 1
fi
nginx -c "$NGX_CONF" -g 'daemon off;' &

exec /app/x-ui
