ARG PHP_VERSION=cli

FROM composer:2 AS composer

FROM php:${PHP_VERSION} AS base

RUN apt-get update \
    && apt-get install -y --no-install-recommends unzip \
    && docker-php-ext-install pdo_mysql pcntl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/local/bin/composer

ENV COMPOSER_ALLOW_SUPERUSER=1

FROM base AS bootstrap

COPY --chmod=755 <<'SCRIPT' /usr/local/bin/scaffold
#!/bin/sh
set -eu
exec 3>&1 1>&2

version=$1
skeleton='*'
if [ "$version" != latest ]; then
    if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
        printf 'LARAVEL_VERSION must be latest, a major, or a release number.\n' >&2
        exit 1
    fi
    skeleton="^${version%%.*}.0"
fi

composer create-project --stability=stable --prefer-dist --no-install --no-scripts --no-interaction \
    laravel/laravel /tmp/backend "$skeleton"
cd /tmp/backend
if [ "$version" != latest ]; then
    case "$version" in
        *.*.*) constraint=$version ;;
        *) constraint="$version.*" ;;
    esac
    composer require --no-update --no-interaction "laravel/framework:$constraint"
fi
composer update --no-install --no-scripts --no-interaction

php <<'PHP'
<?php
$path = 'bootstrap/app.php';
$bootstrap = str_replace('->withRouting(', "->withRouting(\n        api: __DIR__.'/../routes/api.php',", file_get_contents($path), $count);
if ($count !== 1) {
    fwrite(STDERR, "The Laravel starter must support withRouting().\n");
    exit(1);
}
file_put_contents($path, $bootstrap);
PHP

cat > routes/api.php <<'PHP'
<?php

use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    try {
        DB::select('SELECT 1');
    } catch (QueryException) {
        return response()->json(['status' => 'unavailable', 'database' => 'disconnected'], 503);
    }

    return response()->json(['status' => 'ok', 'database' => 'connected']);
});
PHP

cat > .env.example <<'ENV'
APP_NAME="App Local"
APP_ENV=local
APP_KEY=
APP_DEBUG=true
LOG_CHANNEL=stderr
DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
CACHE_STORE=file
SESSION_DRIVER=file
QUEUE_CONNECTION=sync
ENV

cat > .dockerignore <<'IGNORE'
.env*
.git
vendor/
node_modules/
bootstrap/cache/
storage/
IGNORE

exec tar -cf - . >&3
SCRIPT

FROM base AS runtime

WORKDIR /app

COPY composer.json composer.lock ./
RUN composer install --no-interaction --prefer-dist --no-scripts

COPY . .
RUN mkdir -p bootstrap/cache storage/framework/cache/data storage/framework/sessions storage/framework/views storage/logs \
    && php artisan package:discover

COPY --chmod=755 <<'EOF' /usr/local/bin/start-laravel
#!/bin/sh
set -eu

if grep -qx 'APP_KEY=' /app/.env; then
    php artisan key:generate --force --no-interaction
fi

exec "$@"
EOF

ENTRYPOINT ["start-laravel"]
CMD ["php", "artisan", "serve", "--host=0.0.0.0", "--port=8000", "--no-reload"]
