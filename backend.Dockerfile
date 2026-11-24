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
php <<'PHP'
<?php
$path = 'composer.json';
$manifest = json_decode(file_get_contents($path), flags: JSON_THROW_ON_ERROR);
unset(
    $manifest->require->{'laravel/tinker'},
    $manifest->{'require-dev'}->{'fakerphp/faker'},
    $manifest->{'require-dev'}->{'laravel/pail'},
    $manifest->{'require-dev'}->{'laravel/pao'},
    $manifest->scripts->setup,
    $manifest->scripts->dev,
    $manifest->scripts->{'post-update-cmd'},
    $manifest->scripts->{'post-create-project-cmd'},
);
file_put_contents($path, json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR).PHP_EOL);
PHP

rm -f .npmrc AGENTS.md CLAUDE.md README.md package.json vite.config.js \
    app/Models/User.php app/Providers/AppServiceProvider.php \
    config/app.php config/auth.php config/cache.php config/database.php config/logging.php \
    config/mail.php config/queue.php config/services.php config/session.php \
    database/factories/UserFactory.php database/seeders/DatabaseSeeder.php \
    database/migrations/0001_01_01_000000_create_users_table.php \
    database/migrations/0001_01_01_000001_create_cache_table.php \
    database/migrations/0001_01_01_000002_create_jobs_table.php \
    public/.htaccess public/favicon.ico public/robots.txt \
    resources/css/app.css resources/js/app.js resources/js/bootstrap.js resources/views/welcome.blade.php \
    routes/console.php routes/web.php tests/Feature/ExampleTest.php tests/Unit/ExampleTest.php

cat > bootstrap/app.php <<'PHP'
<?php

use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(api: __DIR__.'/../routes/api.php')
    ->withMiddleware()
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })
    ->create();
PHP

cat > bootstrap/providers.php <<'PHP'
<?php

return [];
PHP

cat > config/filesystems.php <<'PHP'
<?php

return [
    'disks' => [
        'local' => [
            'driver' => 'local',
            'root' => storage_path('app/private'),
            'serve' => false,
        ],
    ],
];
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

composer update --no-install --no-scripts --no-interaction

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
