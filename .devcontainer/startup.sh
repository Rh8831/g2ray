#!/usr/bin/env bash
set -euo pipefail

G2RAY_CONFIG_FILE="${G2RAY_CONFIG_FILE:-}"
G2RAY_LISTEN_PORT="${G2RAY_LISTEN_PORT:-}"
G2RAY_UPSTREAM_URL="${G2RAY_UPSTREAM_URL:-}"
G2RAY_LOG_LEVEL="${G2RAY_LOG_LEVEL:-}"
G2RAY_ACCESS_LOG="${G2RAY_ACCESS_LOG:-}"

LOG_LEVELS=(debug info notice warn error crit alert emerg)

normalize_log_level() {
  local level="$1"
  for allowed in "${LOG_LEVELS[@]}"; do
    if [[ "$level" == "$allowed" ]]; then
      printf '%s\n' "$level"
      return 0
    fi
  done

  printf 'warn\n'
  return 1
}

log_level_priority() {
  case "$1" in
    debug) printf '0' ;;
    info) printf '1' ;;
    notice) printf '2' ;;
    warn) printf '3' ;;
    error) printf '4' ;;
    crit) printf '5' ;;
    alert) printf '6' ;;
    emerg) printf '7' ;;
    *) printf '1' ;;
  esac
}

log() {
  local level="$1"
  shift
  local configured_priority
  local message_priority
  configured_priority="$(log_level_priority "${G2RAY_LOG_LEVEL:-info}")"
  message_priority="$(log_level_priority "$level")"

  if (( message_priority < configured_priority )); then
    return 0
  fi

  printf '[%s] level=%s component=startup %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$level" "$*"
}

banner() {
  cat <<'BANNER'

╔════════════════════════════════════════════════════════════╗
║        🚀 G2RAY - XHTTP EDGE RELAY INITIALIZED 🚀        ║
╚════════════════════════════════════════════════════════════╝
BANNER
}

discover_config_file() {
  local candidate

  if [[ -n "$G2RAY_CONFIG_FILE" ]]; then
    printf '%s\n' "$G2RAY_CONFIG_FILE"
    return 0
  fi

  for candidate in \
    /workspaces/*/.devcontainer/config.json \
    /workspace/*/.devcontainer/config.json \
    /app/config.json; do
    if [[ -f "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
}

read_config_value() {
  local config_file="$1"
  local key="$2"

  python3 - "$config_file" "$key" <<'PY'
import json
import sys

config_file = sys.argv[1]
key = sys.argv[2]
aliases = {
    "upstream_url": ("upstreamUrl", "upstream_url", "upstream"),
    "listen_port": ("listenPort", "listen_port", "port"),
    "log_level": ("logLevel", "log_level"),
    "access_log": ("accessLog", "access_log"),
}

try:
    with open(config_file, "r", encoding="utf-8") as fh:
        data = json.load(fh)
except FileNotFoundError:
    sys.exit(0)
except json.JSONDecodeError as exc:
    print(f"Invalid JSON in {config_file}: {exc}", file=sys.stderr)
    sys.exit(1)

for name in aliases[key]:
    value = data.get(name)
    if value is not None and value != "":
        print(value)
        break
PY
}

load_config() {
  local config_file
  config_file="$(discover_config_file || true)"

  if [[ -z "$config_file" || ! -f "$config_file" ]]; then
    return 0
  fi

  if [[ -z "$G2RAY_CONFIG_FILE" ]]; then
    G2RAY_CONFIG_FILE="$config_file"
  fi

  if [[ -z "$G2RAY_UPSTREAM_URL" ]]; then
    G2RAY_UPSTREAM_URL="$(read_config_value "$config_file" upstream_url)"
  fi
  if [[ -z "$G2RAY_LISTEN_PORT" ]]; then
    G2RAY_LISTEN_PORT="$(read_config_value "$config_file" listen_port)"
  fi
  if [[ -z "$G2RAY_LOG_LEVEL" ]]; then
    G2RAY_LOG_LEVEL="$(read_config_value "$config_file" log_level)"
  fi
  if [[ -z "$G2RAY_ACCESS_LOG" ]]; then
    G2RAY_ACCESS_LOG="$(read_config_value "$config_file" access_log)"
  fi
}

hold_for_configuration() {
  cat <<'MESSAGE'

⚠️  G2RAY_UPSTREAM_URL is not configured.

This refactor does not run a VLESS/V2Ray/Xray server in the Codespace.
It only exposes the Codespace as an HTTP(S)/XHTTP relay in front of your own
Xray server.

Set the upstream URL in .devcontainer/config.json:

  {
    "upstreamUrl": "https://your-xray-server.example.com/xhttp"
  }

Or set an environment variable / Codespaces secret:

  G2RAY_UPSTREAM_URL=https://your-xray-server.example.com/xhttp

Optional:

  G2RAY_CONFIG_FILE=/path/to/config.json
  G2RAY_LISTEN_PORT=443
  G2RAY_LOG_LEVEL=info
  G2RAY_ACCESS_LOG=on

The container will stay alive so you can open a shell and configure it.
MESSAGE
  tail -f /dev/null
}

validate_url() {
  local env_name="$1"
  local url="$2"

  python3 - "$env_name" "$url" <<'PY'
import sys
from urllib.parse import urlparse

env_name = sys.argv[1]
url = sys.argv[2]
parsed = urlparse(url)
if parsed.scheme not in {"http", "https"} or not parsed.netloc:
    print(f"{env_name} must be an absolute http:// or https:// URL", file=sys.stderr)
    sys.exit(1)
print(parsed.netloc)
print(parsed.hostname or "")
PY
}

normalize_access_log() {
  case "${G2RAY_ACCESS_LOG,,}" in
    1|true|yes|on) printf '/dev/stdout g2ray_json' ;;
    0|false|no|off) printf 'off' ;;
    *)
      log warn "Invalid G2RAY_ACCESS_LOG='${G2RAY_ACCESS_LOG}'. Falling back to 'on'."
      G2RAY_ACCESS_LOG=on
      printf '/dev/stdout g2ray_json'
      ;;
  esac
}

banner
load_config

G2RAY_LISTEN_PORT="${G2RAY_LISTEN_PORT:-443}"
G2RAY_LOG_LEVEL="${G2RAY_LOG_LEVEL:-info}"
G2RAY_ACCESS_LOG="${G2RAY_ACCESS_LOG:-on}"

if ! normalized_log_level="$(normalize_log_level "$G2RAY_LOG_LEVEL")"; then
  log warn "Invalid G2RAY_LOG_LEVEL='${G2RAY_LOG_LEVEL}'. Falling back to '${normalized_log_level}'."
fi
G2RAY_LOG_LEVEL="$normalized_log_level"

if [[ -n "$G2RAY_CONFIG_FILE" ]]; then
  log info "Loaded relay configuration from ${G2RAY_CONFIG_FILE}."
fi

if [[ -z "$G2RAY_UPSTREAM_URL" ]]; then
  hold_for_configuration
fi

mapfile -t upstream_parts < <(validate_url G2RAY_UPSTREAM_URL "$G2RAY_UPSTREAM_URL")
G2RAY_UPSTREAM_HOST_HEADER="${upstream_parts[0]}"
G2RAY_UPSTREAM_TLS_NAME="${upstream_parts[1]}"

G2RAY_NGINX_ACCESS_LOG="$(normalize_access_log)"
export G2RAY_LISTEN_PORT G2RAY_UPSTREAM_URL G2RAY_UPSTREAM_HOST_HEADER G2RAY_UPSTREAM_TLS_NAME G2RAY_LOG_LEVEL G2RAY_NGINX_ACCESS_LOG

log info "Rendering nginx relay configuration."
envsubst '${G2RAY_LISTEN_PORT} ${G2RAY_UPSTREAM_URL} ${G2RAY_UPSTREAM_HOST_HEADER} ${G2RAY_UPSTREAM_TLS_NAME} ${G2RAY_LOG_LEVEL} ${G2RAY_NGINX_ACCESS_LOG}' \
  < /app/nginx.conf.template > /etc/nginx/nginx.conf

log info "Validating nginx configuration."
nginx -t

cat <<MESSAGE

📋 Relay configuration:
   • Config File: ${G2RAY_CONFIG_FILE:-not found; environment only}
   • Listen Port: ${G2RAY_LISTEN_PORT}
   • Upstream: ${G2RAY_UPSTREAM_URL}
   • Upstream Host Header: ${G2RAY_UPSTREAM_HOST_HEADER}
   • Log Level: ${G2RAY_LOG_LEVEL}
   • Access Log: ${G2RAY_ACCESS_LOG}
   • Local Engine: nginx reverse proxy (no local V2Ray/Xray core)

🔗 Client side:
   • Point your VLESS + XHTTP client at the forwarded Codespaces URL.
   • Keep the XHTTP path compatible with the upstream URL/path above.
   • Terminate/validate real Xray credentials on your own upstream server.

✨ Relay is running...
MESSAGE

log info "Starting nginx relay."
exec nginx -g 'daemon off;'
