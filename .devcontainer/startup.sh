#!/usr/bin/env bash
set -euo pipefail

G2RAY_LISTEN_PORT="${G2RAY_LISTEN_PORT:-443}"
G2RAY_UPSTREAM_URL="${G2RAY_UPSTREAM_URL:-}"
G2RAY_PUBLIC_URL="${G2RAY_PUBLIC_URL:-${G2RAY_EXTERNAL_URL:-}}"
G2RAY_LOG_LEVEL="${G2RAY_LOG_LEVEL:-info}"
G2RAY_ACCESS_LOG="${G2RAY_ACCESS_LOG:-on}"

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
  configured_priority="$(log_level_priority "$G2RAY_LOG_LEVEL")"
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

hold_for_configuration() {
  cat <<'MESSAGE'

⚠️  G2RAY_UPSTREAM_URL is not configured.

This refactor does not run a VLESS/V2Ray/Xray server in the Codespace.
It only exposes the container as an HTTP(S)/XHTTP relay in front of your own
Xray server.

Set one Codespaces secret or environment variable, then rebuild/restart:

  G2RAY_UPSTREAM_URL=https://your-xray-server.example.com/xhttp

Optional:

  G2RAY_LISTEN_PORT=443
  G2RAY_PUBLIC_URL=https://relay.example.com
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

detect_codespaces_url() {
  if [[ -n "${CODESPACE_NAME:-}" && -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]]; then
    printf 'https://%s-%s.%s\n' \
      "$CODESPACE_NAME" \
      "$G2RAY_LISTEN_PORT" \
      "$GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"
  fi
}

normalize_access_log() {
  case "${G2RAY_ACCESS_LOG,,}" in
    1|true|yes|on) printf '/dev/stdout g2ray_json' ;;
    0|false|no|off) printf 'off' ;;
    *)
      log warn "Invalid G2RAY_ACCESS_LOG='${G2RAY_ACCESS_LOG}'. Falling back to 'on'."
      printf '/dev/stdout g2ray_json'
      ;;
  esac
}

banner

if ! normalized_log_level="$(normalize_log_level "$G2RAY_LOG_LEVEL")"; then
  log warn "Invalid G2RAY_LOG_LEVEL='${G2RAY_LOG_LEVEL}'. Falling back to '${normalized_log_level}'."
fi
G2RAY_LOG_LEVEL="$normalized_log_level"

if [[ -z "$G2RAY_UPSTREAM_URL" ]]; then
  hold_for_configuration
fi

mapfile -t upstream_parts < <(validate_url G2RAY_UPSTREAM_URL "$G2RAY_UPSTREAM_URL")
G2RAY_UPSTREAM_HOST_HEADER="${upstream_parts[0]}"
G2RAY_UPSTREAM_TLS_NAME="${upstream_parts[1]}"

if [[ -n "$G2RAY_PUBLIC_URL" ]]; then
  validate_url G2RAY_PUBLIC_URL "$G2RAY_PUBLIC_URL" >/dev/null
else
  G2RAY_PUBLIC_URL="$(detect_codespaces_url)"
fi

G2RAY_NGINX_ACCESS_LOG="$(normalize_access_log)"
export G2RAY_LISTEN_PORT G2RAY_UPSTREAM_URL G2RAY_UPSTREAM_HOST_HEADER G2RAY_UPSTREAM_TLS_NAME G2RAY_LOG_LEVEL G2RAY_NGINX_ACCESS_LOG

log info "Rendering nginx relay configuration."
envsubst '${G2RAY_LISTEN_PORT} ${G2RAY_UPSTREAM_URL} ${G2RAY_UPSTREAM_HOST_HEADER} ${G2RAY_UPSTREAM_TLS_NAME} ${G2RAY_LOG_LEVEL} ${G2RAY_NGINX_ACCESS_LOG}' \
  < /app/nginx.conf.template > /etc/nginx/nginx.conf

log info "Validating nginx configuration."
nginx -t

cat <<MESSAGE

📋 Relay configuration:
   • Listen Port: ${G2RAY_LISTEN_PORT}
   • Upstream: ${G2RAY_UPSTREAM_URL}
   • Upstream Host Header: ${G2RAY_UPSTREAM_HOST_HEADER}
   • Public Client URL: ${G2RAY_PUBLIC_URL:-not set; use your forwarded/tunnel URL}
   • Log Level: ${G2RAY_LOG_LEVEL}
   • Access Log: ${G2RAY_ACCESS_LOG}
   • Local Engine: nginx reverse proxy (no local V2Ray/Xray core)

🔗 Client side:
   • Point your VLESS + XHTTP client at the Public Client URL above.
   • Set G2RAY_PUBLIC_URL if you use a custom domain, tunnel, or non-Codespaces URL.
   • Keep the XHTTP path compatible with the upstream URL/path above.
   • Terminate/validate real Xray credentials on your own upstream server.

✨ Relay is running...
MESSAGE

log info "Starting nginx relay."
exec nginx -g 'daemon off;'
