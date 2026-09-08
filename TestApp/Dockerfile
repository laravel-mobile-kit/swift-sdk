# The Laravel compatibility fixture for the Swift integration tests.
#
# The application is built from the official skeleton inside the image and the
# repository's overlay is applied on top of it, so what the tests run against is
# a real Laravel installation rather than a hand-written stand-in.
FROM php:8.3-cli

RUN apt-get update \
    && apt-get install -y --no-install-recommends git unzip libzip-dev libsqlite3-dev \
    && docker-php-ext-install zip pdo_sqlite \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

ENV APP_DIR=/opt/laravel \
    HOST=0.0.0.0 \
    PORT=8000

WORKDIR /opt/fixture
COPY scripts ./scripts
COPY overlay ./overlay

RUN bash scripts/build-app.sh

EXPOSE 8000

# serve.sh re-applies the overlay and re-seeds, so every container start hands
# the tests the same data.
CMD ["bash", "scripts/serve.sh"]
