#!/usr/bin/env bash
#
# Builds the Laravel fixture from the official skeleton and applies this
# repository's overlay on top of it.
#
# The generated application lives in TestApp/.laravel and is disposable: delete
# the directory to rebuild from scratch. Only the overlay is version-controlled,
# so the fixture stays a real, unmodified Laravel application plus our routes.

set -euo pipefail

TESTAPP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${APP_DIR:-$TESTAPP_DIR/.laravel}"
LARAVEL_VERSION="${LARAVEL_VERSION:-^12.0}"

if [[ ! -f "$APP_DIR/artisan" ]]; then
    echo "==> Creating a Laravel $LARAVEL_VERSION application in $APP_DIR"
    composer create-project "laravel/laravel:$LARAVEL_VERSION" "$APP_DIR" \
        --no-interaction --prefer-dist --quiet

    echo "==> Installing the API scaffolding (Sanctum, routes/api.php)"
    php "$APP_DIR/artisan" install:api --no-interaction --without-migration-prompt

    # install:api publishes Sanctum's migration through a sub-process that stays
    # silent when it fails, so it is published explicitly here.
    php "$APP_DIR/artisan" vendor:publish --tag=sanctum-migrations --no-interaction >/dev/null
fi

if ! ls "$APP_DIR"/database/migrations/*create_personal_access_tokens_table.php >/dev/null 2>&1; then
    echo "error: Sanctum's migration was not published; delete $APP_DIR and retry" >&2
    exit 1
fi

echo "==> Applying the fixture overlay"
cp -R "$TESTAPP_DIR/overlay/." "$APP_DIR/"

echo "==> Configuring the environment"
touch "$APP_DIR/database/database.sqlite"
php "$TESTAPP_DIR/scripts/configure-env.php" "$APP_DIR/.env"

echo "==> Migrating and seeding"
php "$APP_DIR/artisan" migrate:fresh --seed --force --no-interaction >/dev/null
php "$APP_DIR/artisan" config:clear >/dev/null

echo "==> Fixture ready in $APP_DIR"
