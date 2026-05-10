#!/usr/bin/env bash
set -euo pipefail

echo "🧹 Preparing nginx relay runtime directories..."
mkdir -p /run/nginx /var/cache/nginx /var/log/nginx
rm -f /etc/nginx/sites-enabled/default

echo "✅ Relay base image is ready. No local V2Ray/Xray core is installed."
