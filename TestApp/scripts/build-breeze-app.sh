#!/usr/bin/env bash
#
# Builds the second fixture: Laravel's own API starter kit, untouched.
#
# The point of this one is that nothing in it is ours. `breeze:install api`
# generates the routes, controllers, and requests, and the SDK is tested against
# whatever Laravel ships — including its authentication contract, which is
# Sanctum's cookie-based SPA session rather than bearer tokens.
#
# The application lands in TestApp/.breeze and is disposable.

set -euo pipefail

TESTAPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${BREEZE_APP_DIR:-$TESTAPP_DIR/.breeze}"
LARAVEL_VERSION="${LARAVEL_VERSION:-^12.0}"
HOST="${BREEZE_HOST:-127.0.0.1}"
PORT="${BREEZE_PORT:-8200}"
APP_URL="http://$HOST:$PORT"

if [[ ! -f "$APP_DIR/artisan" ]]; then
    echo "==> Creating a Laravel $LARAVEL_VERSION application in $APP_DIR"
    composer create-project "laravel/laravel:$LARAVEL_VERSION" "$APP_DIR" \
        --no-interaction --prefer-dist --quiet

    # Breeze shells out to `php artisan install:api` from its own working
    # directory, which fails when artisan is not in the current one — so the
    # API scaffolding is installed first, and Breeze is layered on top.
    echo "==> Installing the API scaffolding (Sanctum, routes/api.php)"
    php "$APP_DIR/artisan" install:api --no-interaction --without-migration-prompt
    php "$APP_DIR/artisan" vendor:publish --tag=sanctum-migrations --no-interaction >/dev/null

    echo "==> Installing the Breeze API starter kit"
    composer require laravel/breeze --dev --working-dir="$APP_DIR" --no-interaction --quiet
    php "$APP_DIR/artisan" breeze:install api --no-interaction
fi

if ! grep -q "routes/api.php" "$APP_DIR/bootstrap/app.php"; then
    echo "error: the API routes were never registered in bootstrap/app.php" >&2
    exit 1
fi

echo "==> Configuring the environment"
touch "$APP_DIR/database/database.sqlite"
php "$TESTAPP_DIR/scripts/configure-env.php" "$APP_DIR/.env"

# Sanctum only treats a request as stateful when it comes from a domain listed
# here, which for these tests is the fixture's own host.
php "$TESTAPP_DIR/scripts/configure-env.php" "$APP_DIR/.env" \
    "APP_URL=$APP_URL" \
    "FRONTEND_URL=$APP_URL" \
    "SANCTUM_STATEFUL_DOMAINS=$HOST:$PORT,localhost:$PORT" \
    "SESSION_DOMAIN=$HOST"

echo "==> Migrating and seeding"
php "$APP_DIR/artisan" migrate:fresh --seed --force --no-interaction >/dev/null
php "$APP_DIR/artisan" config:clear >/dev/null

echo "==> Breeze fixture ready in $APP_DIR"
