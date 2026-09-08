#!/usr/bin/env bash
#
# Builds the fixture if needed and serves it, so the Swift integration tests can
# run without Docker:
#
#   TestApp/scripts/serve.sh
#   LARAVEL_TEST_URL=http://127.0.0.1:8000 swift test

set -euo pipefail

TESTAPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-$TESTAPP_DIR/.laravel}"
HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-8000}"

"$TESTAPP_DIR/scripts/build-app.sh"

echo "==> Serving the fixture on http://$HOST:$PORT"
exec php "$APP_DIR/artisan" serve --host "$HOST" --port "$PORT"
