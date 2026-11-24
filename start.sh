#!/bin/sh
set -eu

cd "$(dirname "$0")"

seed_env() {
    if [ ! -e "$1/.env" ]; then
        (umask 077; set -C; cat "$1/.env.example" > "$1/.env")
    fi
}

seed_env .

settings=$(docker compose config --environment --no-env-resolution)
setting() {
    printf '%s\n' "$settings" | sed -n "s/^$1=//p"
}

scratch=
cleanup() {
    if [ -n "$scratch" ]; then
        rm -rf -- "$scratch"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

create_application() {
    if [ -e "../$1" ]; then
        return
    fi
    application=$1 recipe=$2 version=$3
    shift 3

    printf 'Creating %s...\n' "$application"
    scratch=$(mktemp -d ../.app-local.XXXXXX)
    image=$(docker build --pull --quiet --target bootstrap "$@" - < "$recipe")
    docker run --rm "$image" scaffold "${version:-latest}" > "$scratch/project.tar"
    mkdir "$scratch/project"
    tar -xf "$scratch/project.tar" -C "$scratch/project"
    mv "$scratch/project" "../$application"
    cleanup
    scratch=
}

php_version=$(setting PHP_VERSION)
create_application backend backend.Dockerfile "$(setting LARAVEL_VERSION)" \
    --build-arg "PHP_VERSION=${php_version:-cli}"
create_application frontend frontend.Dockerfile "$(setting REACT_VERSION)"

seed_env ../backend
seed_env ../frontend

exec docker compose up -d --build --wait
