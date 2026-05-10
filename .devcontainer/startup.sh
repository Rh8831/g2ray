#!/usr/bin/env bash
set -euo pipefail

G2RAY_LISTEN_PORT="${G2RAY_LISTEN_PORT:-443}"
G2RAY_UPSTREAM_URL="${G2RAY_UPSTREAM_URL:-}"

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
It only exposes the Codespace as an HTTP(S)/XHTTP relay in front of your own
Xray server.

Set one Codespaces secret or environment variable, then rebuild/restart:

  G2RAY_UPSTREAM_URL=https://your-xray-server.example.com/xhttp

Optional:

  G2RAY_LISTEN_PORT=443

The container will stay alive so you can open a shell and configure it.
MESSAGE
  tail -f /dev/null
}

validate_url() {
  python3 - "$G2RAY_UPSTREAM_URL" <<'PY'
import sys
from urllib.parse import urlparse

url = sys.argv[1]
parsed = urlparse(url)
if parsed.scheme not in {"http", "https"} or not parsed.netloc:
    print("G2RAY_UPSTREAM_URL must be an absolute http:// or https:// URL", file=sys.stderr)
    sys.exit(1)
print(parsed.netloc)
print(parsed.hostname or "")
PY
}

banner

if [[ -z "$G2RAY_UPSTREAM_URL" ]]; then
  hold_for_configuration
fi

mapfile -t upstream_parts < <(validate_url)
G2RAY_UPSTREAM_HOST_HEADER="${upstream_parts[0]}"
G2RAY_UPSTREAM_TLS_NAME="${upstream_parts[1]}"
export G2RAY_LISTEN_PORT G2RAY_UPSTREAM_URL G2RAY_UPSTREAM_HOST_HEADER G2RAY_UPSTREAM_TLS_NAME

envsubst '${G2RAY_LISTEN_PORT} ${G2RAY_UPSTREAM_URL} ${G2RAY_UPSTREAM_HOST_HEADER} ${G2RAY_UPSTREAM_TLS_NAME}' \
  < /app/nginx.conf.template > /etc/nginx/nginx.conf

nginx -t

cat <<MESSAGE

📋 Relay configuration:
   • Listen Port: ${G2RAY_LISTEN_PORT}
   • Upstream: ${G2RAY_UPSTREAM_URL}
   • Upstream Host Header: ${G2RAY_UPSTREAM_HOST_HEADER}
   • Local Engine: nginx reverse proxy (no local V2Ray/Xray core)

🔗 Client side:
   • Point your VLESS + XHTTP client at the forwarded Codespaces URL.
   • Keep the XHTTP path compatible with the upstream URL/path above.
   • Terminate/validate real Xray credentials on your own upstream server.

✨ Relay is running...
MESSAGE

exec nginx -g 'daemon off;'
