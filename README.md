# App Local development

The `app_local` Compose project runs PHP and Laravel, React with Vite, and MySQL. The startup files in this directory are enough to generate the environment. You need Docker with Compose and internet access on the first run.

## Start

Run `./start.sh` from this directory, or `./docker/start.sh` from the parent directory. If `backend/` or `frontend/` is missing, the script creates it next to `docker/` using Composer's Laravel project generator or Vite's React generator inside Docker. It also configures the API and MySQL connection, creates missing `.env` files, and starts the three services. Existing apps and settings are kept. On first startup, Laravel fills an empty `APP_KEY=` in `backend/.env`.

Open the React app at <http://localhost:5173>. It calls `GET /api/health` through Vite and shows whether the API can query MySQL. To check the same endpoint directly and through Vite, run these commands from the Docker directory.

```sh
docker compose ps
curl -fsS http://localhost:8000/api/health
curl -fsS http://localhost:5173/api/health
```

Both requests should return `{"status":"ok","database":"connected"}`. Compose waits for MySQL before starting Laravel, then waits for Laravel before starting React. Use `docker compose logs -f` to follow startup logs.

The Laravel starter is API-only. Its sole initial route is `GET /api/health`. The web welcome page, file-serving routes, and demo migrations are omitted. Laravel uses its built-in configuration defaults with the local environment settings.

## Versions

The defaults select `php:cli`, the latest stable compatible Laravel, `react@latest`, and `mysql:latest`. To pin versions, set them in `docker/.env` or pass them before the startup command. For example, from this directory:

```sh
PHP_VERSION=8.4-cli LARAVEL_VERSION=12 REACT_VERSION=18 MYSQL_VERSION=8.4 ./start.sh
```

`PHP_VERSION` and `MYSQL_VERSION` are Docker image tags. `LARAVEL_VERSION` accepts a major, minor, or exact release for Laravel 11 and newer. `REACT_VERSION` accepts an npm version for React 18 and newer. Laravel and React selectors apply when generating a missing app. Existing apps keep the versions in their lockfiles. MySQL data is stored in a named volume per image tag, so choosing a different tag starts a separate database.

## Environment Files

Paths below are relative to the project root. Each `.env` is editable on the host and ignored by Git. The generated `backend/` and `frontend/` directories are also ignored. The Dockerfiles contain the setup commands for generated projects.

| File | Contents |
| --- | --- |
| `backend/.env` | Laravel settings, including `APP_KEY` and SMTP credentials. Mounted directly at `/app/.env`. |
| `frontend/.env` | Public Vite settings. `VITE_API_BASE_URL=/api` sends requests through Vite's proxy. |
| `docker/.env` | Published ports and the MySQL credentials shared by Laravel and MySQL. Compose derives Laravel's `APP_URL` from `BACKEND_PORT`. |

Keep secrets in `backend/.env` or `docker/.env`. Vite embeds `VITE_` values in browser code. [Vite environment variables](https://vite.dev/guide/env-and-mode).

After editing `backend/.env`, run `docker compose up -d --no-deps --force-recreate backend` from `docker/` so any file replaced by your editor is mounted again. For changes to `frontend/.env` or `docker/.env`, rerun `./docker/start.sh` from the project root. MySQL uses its credential variables when initializing a fresh database volume. Change existing MySQL users in MySQL before changing their credentials in `docker/.env`.

## Develop

- Changes under `../frontend/src` are hot-reloaded. Changes under `../backend/app`, `../backend/config`, `../backend/database`, and `../backend/routes` are visible on the next request.
- After changing dependency lockfiles, Dockerfiles, or other files baked into the images, rerun `./docker/start.sh` from the project root. The backend image installs PHP dependencies with `composer install`.
- Once you add Laravel migrations, apply them with `docker compose exec backend php artisan migrate`.
- Compose puts all three services on its default project network. Vite forwards `/api` to `backend:8000`, and Laravel reaches MySQL at `db:3306`. The two web ports bind to localhost and MySQL is reachable from containers on the Compose network.

## Stop

Run `docker compose down` from `docker/`. This keeps the local `.env` files and the `mysql-data` volume. `docker compose down -v` deletes the database volume.
