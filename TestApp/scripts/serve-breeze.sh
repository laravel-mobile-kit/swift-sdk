#!/usr/bin/env bash
#
# Builds the Breeze starter-kit fixture if needed and serves it:
#
#   TestApp/scripts/serve-breeze.sh
#   LARAVEL_BREEZE_URL=http://127.0.0.1:8200 swift test --filter StarterKit

set -euo pipefail

TESTAPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${BREEZE_APP_DIR:-$TESTAPP_DIR/.breeze}"
HOST="${BREEZE_HOST:-127.0.0.1}"
PORT="${BREEZE_PORT:-8200}"

"$TESTAPP_DIR/scripts/build-breeze-app.sh"

echo "==> Serving the Breeze fixture on http://$HOST:$PORT"
exec php "$APP_DIR/artisan" serve --host "$HOST" --port "$PORT"
